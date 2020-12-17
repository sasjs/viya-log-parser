%global appLoc;
%let appLoc=%sysfunc(coalescec(&appLoc,/Public/sasjs/log-parser)); /* metadata or files service location of your app */
%let syscc=0;
options ps=max noquotelenmax;
%macro mp_abort(mac=mp_abort.sas, type=, msg=, iftrue=%str(1=1)
)/*/STORE SOURCE*/;
  %if not(%eval(%unquote(&iftrue))) %then %return;
  %put NOTE: ///  mp_abort macro executing //;
  %if %length(&mac)>0 %then %put NOTE- called by &mac;
  %put NOTE - &msg;
  /* Stored Process Server web app context */
  %if %symexist(_metaperson)
  or (%symexist(SYSPROCESSNAME) and "&SYSPROCESSNAME"="Compute Server" )
  %then %do;
    options obs=max replace nosyntaxcheck mprint;
    /* extract log errs / warns, if exist */
    %local logloc logline;
    %global logmsg; /* capture global messages */
    %if %symexist(SYSPRINTTOLOG) %then %let logloc=&SYSPRINTTOLOG;
    %else %let logloc=%qsysfunc(getoption(LOG));
    proc printto log=log;run;
    %if %length(&logloc)>0 %then %do;
      %let logline=0;
      data _null_;
        infile &logloc lrecl=5000;
        input; putlog _infile_;
        i=1;
        retain logonce 0;
        if (_infile_=:"%str(WARN)ING" or _infile_=:"%str(ERR)OR") and logonce=0 then do;
          call symputx('logline',_n_);
          logonce+1;
        end;
      run;
      /* capture log including lines BEFORE the err */
      %if &logline>0 %then %do;
        data _null_;
          infile &logloc lrecl=5000;
          input;
          i=1;
          stoploop=0;
          if _n_ ge &logline-5 and stoploop=0 then do until (i>12);
            call symputx('logmsg',catx('\n',symget('logmsg'),_infile_));
            input;
            i+1;
            stoploop=1;
          end;
          if stoploop=1 then stop;
        run;
      %end;
    %end;
    %if %symexist(SYS_JES_JOB_URI) %then %do;
      /* setup webout */
      OPTIONS NOBOMFILE;
      %if "X&SYS_JES_JOB_URI.X"="XX" %then %do;
          filename _webout temp lrecl=999999 mod;
      %end;
      %else %do;
        filename _webout filesrvc parenturi="&SYS_JES_JOB_URI"
          name="_webout.json" lrecl=999999 mod;
      %end;
    %end;
    /* send response in SASjs JSON format */
    data _null_;
      file _webout mod lrecl=32000;
      length msg $32767 debug $8;
      sasdatetime=datetime();
      msg=cats(symget('msg'),'\n\nLog Extract:\n',symget('logmsg'));
      /* escape the quotes */
      msg=tranwrd(msg,'"','\"');
      /* ditch the CRLFs as chrome complains */
      msg=compress(msg,,'kw');
      /* quote without quoting the quotes (which are escaped instead) */
      msg=cats('"',msg,'"');
      if symexist('_debug') then debug=quote(trim(symget('_debug')));
      else debug='""';
      if debug ge '"131"' then put '>>weboutBEGIN<<';
      put '{"START_DTTM" : "' "%sysfunc(datetime(),datetime20.3)" '"';
      put ',"sasjsAbort" : [{';
      put ' "MSG":' msg ;
      put ' ,"MAC": "' "&mac" '"}]';
      put ",""SYSUSERID"" : ""&sysuserid"" ";
      put ',"_DEBUG":' debug ;
      if symexist('_metauser') then do;
        _METAUSER=quote(trim(symget('_METAUSER')));
        put ",""_METAUSER"": " _METAUSER;
        _METAPERSON=quote(trim(symget('_METAPERSON')));
        put ',"_METAPERSON": ' _METAPERSON;
      end;
      if symexist('SYS_JES_JOB_URI') then do;
        SYS_JES_JOB_URI=quote(trim(symget('SYS_JES_JOB_URI')));
        put ',"SYS_JES_JOB_URI": ' SYS_JES_JOB_URI;
      end;
      _PROGRAM=quote(trim(resolve(symget('_PROGRAM'))));
      put ',"_PROGRAM" : ' _PROGRAM ;
      put ",""SYSCC"" : ""&syscc"" ";
      put ",""SYSERRORTEXT"" : ""&syserrortext"" ";
      put ",""SYSJOBID"" : ""&sysjobid"" ";
      put ",""SYSWARNINGTEXT"" : ""&syswarningtext"" ";
      put ',"END_DTTM" : "' "%sysfunc(datetime(),datetime20.3)" '" ';
      put "}" @;
      if debug ge '"131"' then put '>>weboutEND<<';
    run;
    %let syscc=0;
    %if %symexist(_metaport) %then %do;
      data _null_;
        if symexist('sysprocessmode')
         then if symget("sysprocessmode")="SAS Stored Process Server"
          then rc=stpsrvset('program error', 0);
      run;
    %end;
    /**
     * endsas is reliable but kills some deployments.
     * Abort variants are ungraceful (non zero return code)
     * This approach lets SAS run silently until the end :-)
     */
    %put _all_;
    filename skip temp;
    data _null_;
      file skip;
      put '%macro skip(); %macro skippy();';
    run;
    %inc skip;
  %end;
  %else %do;
    %put _all_;
    %abort cancel;
  %end;
%mend;
%macro mf_getuniquefileref(prefix=mcref,maxtries=1000);
  %local x fname;
  %let x=0;
  %do x=0 %to &maxtries;
  %if %sysfunc(fileref(&prefix&x)) > 0 %then %do;
    %let fname=&prefix&x;
    %let rc=%sysfunc(filename(fname,,temp));
    %if &rc %then %put %sysfunc(sysmsg());
    &prefix&x
    %*put &sysmacroname: Fileref &prefix&x was assigned and returned;
    %return;
  %end;
  %end;
  %put unable to find available fileref in range &prefix.0-&maxtries;
%mend;
%macro mf_getuniquelibref(prefix=mclib,maxtries=1000);
  %local x libref;
  %let x=0;
  %do x=0 %to &maxtries;
  %if %sysfunc(libref(&prefix&x)) ne 0 %then %do;
    %let libref=&prefix&x;
    %let rc=%sysfunc(libname(&libref,%sysfunc(pathname(work))));
    %if &rc %then %put %sysfunc(sysmsg());
    &prefix&x
    %*put &sysmacroname: Libref &libref assigned as WORK and returned;
    %return;
  %end;
  %end;
  %put unable to find available libref in range &prefix.0-&maxtries;
%mend;
%macro mf_isblank(param
)/*/STORE SOURCE*/;
  %sysevalf(%superq(param)=,boolean)
%mend;
%macro mf_mval(var);
  %if %symexist(&var) %then %do;
    %superq(&var)
  %end;
%mend;
%macro mf_trimstr(basestr,trimstr);
%local baselen trimlen trimval;
/* return if basestr is shorter than trimstr (or 0) */
%let baselen=%length(%superq(basestr));
%let trimlen=%length(%superq(trimstr));
%if &baselen < &trimlen or &baselen=0 %then %return;
/* obtain the characters from the end of basestr */
%let trimval=%qsubstr(%superq(basestr)
  ,%length(%superq(basestr))-&trimlen+1
  ,&trimlen);
/* compare and if matching, chop it off! */
%if %superq(basestr)=%superq(trimstr) %then %do;
  %return;
%end;
%else %if %superq(trimval)=%superq(trimstr) %then %do;
  %qsubstr(%superq(basestr),1,%length(%superq(basestr))-&trimlen)
%end;
%else %do;
  &basestr
%end;
%mend;
%macro mf_getplatform(switch
)/*/STORE SOURCE*/;
%local a b c;
%if &switch.NONE=NONE %then %do;
  %if %symexist(sysprocessmode) %then %do;
    %if "&sysprocessmode"="SAS Object Server"
    or "&sysprocessmode"= "SAS Compute Server" %then %do;
        SASVIYA
    %end;
    %else %if "&sysprocessmode"="SAS Stored Process Server" %then %do;
      SASMETA
      %return;
    %end;
    %else %do;
      SAS
      %return;
    %end;
  %end;
  %else %if %symexist(_metaport) %then %do;
    SASMETA
    %return;
  %end;
  %else %do;
    SAS
    %return;
  %end;
%end;
%else %if &switch=SASSTUDIO %then %do;
  /* return the version of SAS Studio else 0 */
  %if %mf_mval(_CLIENTAPP)=%str(SAS Studio) %then %do;
    %let a=%mf_mval(_CLIENTVERSION);
    %let b=%scan(&a,1,.);
    %if %eval(&b >2) %then %do;
      &b
    %end;
    %else 0;
  %end;
  %else 0;
%end;
%else %if &switch=VIYARESTAPI %then %do;
  %mf_trimstr(%sysfunc(getoption(servicesbaseurl)),/)
%end;
%mend;
%macro mv_createfolder(path=
    ,access_token_var=ACCESS_TOKEN
    ,grant_type=sas_services
  );
%local oauth_bearer;
%if &grant_type=detect %then %do;
  %if %symexist(&access_token_var) %then %let grant_type=authorization_code;
  %else %let grant_type=sas_services;
%end;
%if &grant_type=sas_services %then %do;
    %let oauth_bearer=oauth_bearer=sas_services;
    %let &access_token_var=;
%end;
%put &sysmacroname: grant_type=&grant_type;
%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password
    and &grant_type ne sas_services
  )
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)
%mp_abort(iftrue=(%mf_isblank(&path)=1)
  ,mac=&sysmacroname
  ,msg=%str(path value must be provided)
)
%mp_abort(iftrue=(%length(&path)=1)
  ,mac=&sysmacroname
  ,msg=%str(path value must be provided)
)
options noquotelenmax;
%local subfolder_cnt; /* determine the number of subfolders */
%let subfolder_cnt=%sysfunc(countw(&path,/));
%local href; /* resource address (none for root) */
%let href="/folders/folders?parentFolderUri=/folders/folders/none";
%local base_uri; /* location of rest apis */
%let base_uri=%mf_getplatform(VIYARESTAPI);
%local x newpath subfolder;
%do x=1 %to &subfolder_cnt;
  %let subfolder=%scan(&path,&x,%str(/));
  %let newpath=&newpath/&subfolder;
  %local fname1;
  %let fname1=%mf_getuniquefileref();
  %put &sysmacroname checking to see if &newpath exists;
  proc http method='GET' out=&fname1 &oauth_bearer
      url="&base_uri/folders/folders/@item?path=&newpath";
  %if &grant_type=authorization_code %then %do;
      headers "Authorization"="Bearer &&&access_token_var";
  %end;
  run;
  %local libref1;
  %let libref1=%mf_getuniquelibref();
  libname &libref1 JSON fileref=&fname1;
  %mp_abort(iftrue=(&SYS_PROCHTTP_STATUS_CODE ne 200 and &SYS_PROCHTTP_STATUS_CODE ne 404)
    ,mac=&sysmacroname
    ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
  )
  %if &SYS_PROCHTTP_STATUS_CODE=200 %then %do;
    %put &sysmacroname &newpath exists so grab the follow on link ;
    data _null_;
      set &libref1..links;
      if rel='createChild' then
        call symputx('href',quote("&base_uri"!!trim(href)),'l');
    run;
  %end;
  %else %if &SYS_PROCHTTP_STATUS_CODE=404 %then %do;
    %put &sysmacroname &newpath not found - creating it now;
    %local fname2;
    %let fname2=%mf_getuniquefileref();
    data _null_;
      length json $1000;
      json=cats("'"
        ,'{"name":'
        ,quote(trim(symget('subfolder')))
        ,',"description":'
        ,quote("&subfolder, created by &sysmacroname")
        ,',"type":"folder"}'
        ,"'"
      );
      call symputx('json',json,'l');
    run;
    proc http method='POST'
        in=&json
        out=&fname2
        &oauth_bearer
        url=%unquote(%superq(href));
        headers
      %if &grant_type=authorization_code %then %do;
                "Authorization"="Bearer &&&access_token_var"
      %end;
                'Content-Type'='application/vnd.sas.content.folder+json'
                'Accept'='application/vnd.sas.content.folder+json';
    run;
    %put &=SYS_PROCHTTP_STATUS_CODE;
    %put &=SYS_PROCHTTP_STATUS_PHRASE;
    %mp_abort(iftrue=(&SYS_PROCHTTP_STATUS_CODE ne 201)
      ,mac=&sysmacroname
      ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
    )
    %local libref2;
    %let libref2=%mf_getuniquelibref();
    libname &libref2 JSON fileref=&fname2;
    %put &sysmacroname &newpath now created. Grabbing the follow on link ;
    data _null_;
      set &libref2..links;
      if rel='createChild' then
        call symputx('href',quote(trim(href)),'l');
    run;
    libname &libref2 clear;
    filename &fname2 clear;
  %end;
  filename &fname1 clear;
  libname &libref1 clear;
%end;
%mend;
%macro mv_deletejes(path=
    ,name=
    ,access_token_var=ACCESS_TOKEN
    ,grant_type=sas_services
  );
%local oauth_bearer;
%if &grant_type=detect %then %do;
  %if %symexist(&access_token_var) %then %let grant_type=authorization_code;
  %else %let grant_type=sas_services;
%end;
%if &grant_type=sas_services %then %do;
    %let oauth_bearer=oauth_bearer=sas_services;
    %let &access_token_var=;
%end;
%put &sysmacroname: grant_type=&grant_type;
%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password
    and &grant_type ne sas_services
  )
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)
%mp_abort(iftrue=(%mf_isblank(&path)=1)
  ,mac=&sysmacroname
  ,msg=%str(path value must be provided)
)
%mp_abort(iftrue=(%mf_isblank(&name)=1)
  ,mac=&sysmacroname
  ,msg=%str(name value must be provided)
)
%mp_abort(iftrue=(%length(&path)=1)
  ,mac=&sysmacroname
  ,msg=%str(path value must be provided)
)
options noquotelenmax;
%local base_uri; /* location of rest apis */
%let base_uri=%mf_getplatform(VIYARESTAPI);
%put &sysmacroname: fetching details for &path ;
%local fname1;
%let fname1=%mf_getuniquefileref();
proc http method='GET' out=&fname1 &oauth_bearer
  url="&base_uri/folders/folders/@item?path=&path";
%if &grant_type=authorization_code %then %do;
  headers "Authorization"="Bearer &&&access_token_var";
%end;
run;
%if &SYS_PROCHTTP_STATUS_CODE=404 %then %do;
  %put &sysmacroname: Folder &path NOT FOUND - nothing to delete!;
  %return;
%end;
%else %if &SYS_PROCHTTP_STATUS_CODE ne 200 %then %do;
  /*data _null_;infile &fname1;input;putlog _infile_;run;*/
  %mp_abort(mac=&sysmacroname
    ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
  )
%end;
%put &sysmacroname: grab the follow on link ;
%local libref1;
%let libref1=%mf_getuniquelibref();
libname &libref1 JSON fileref=&fname1;
data _null_;
  set &libref1..links;
  if rel='members' then call symputx('mref',quote("&base_uri"!!trim(href)),'l');
run;
/* get the children */
%local fname1a;
%let fname1a=%mf_getuniquefileref();
proc http method='GET' out=&fname1a &oauth_bearer
  url=%unquote(%superq(mref));
%if &grant_type=authorization_code %then %do;
  headers "Authorization"="Bearer &&&access_token_var";
%end;
run;
%put &=SYS_PROCHTTP_STATUS_CODE;
%local libref1a;
%let libref1a=%mf_getuniquelibref();
libname &libref1a JSON fileref=&fname1a;
%local uri found;
%let found=0;
%put Getting object uri from &libref1a..items;
data _null_;
  set &libref1a..items;
  if contenttype='jobDefinition' and upcase(name)="%upcase(&name)" then do;
    call symputx('uri',cats("&base_uri",uri),'l');
    call symputx('found',1,'l');
  end;
run;
%if &found=0 %then %do;
  %put NOTE:;%put NOTE- &sysmacroname: &path/&name NOT FOUND;%put NOTE- ;
  %return;
%end;
proc http method="DELETE" url="&uri" &oauth_bearer;
  headers
%if &grant_type=authorization_code %then %do;
      "Authorization"="Bearer &&&access_token_var"
%end;
      "Accept"="*/*";/**/
run;
%if &SYS_PROCHTTP_STATUS_CODE ne 204 %then %do;
  data _null_; infile &fname2; input; putlog _infile_;run;
  %mp_abort(mac=&sysmacroname
    ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
  )
%end;
%else %put &sysmacroname: &path/&name successfully deleted;
/* clear refs */
filename &fname1 clear;
libname &libref1 clear;
filename &fname1a clear;
libname &libref1a clear;
%mend;
%macro mv_createwebservice(path=
    ,name=
    ,desc=Created by the mv_createwebservice.sas macro
    ,precode=
    ,code=ft15f001
    ,access_token_var=ACCESS_TOKEN
    ,grant_type=sas_services
    ,replace=YES
    ,adapter=sasjs
    ,debug=0
    ,contextname=
  );
%local oauth_bearer;
%if &grant_type=detect %then %do;
  %if %symexist(&access_token_var) %then %let grant_type=authorization_code;
  %else %let grant_type=sas_services;
%end;
%if &grant_type=sas_services %then %do;
    %let oauth_bearer=oauth_bearer=sas_services;
    %let &access_token_var=;
%end;
%put &sysmacroname: grant_type=&grant_type;
/* initial validation checking */
%mp_abort(iftrue=(&grant_type ne authorization_code and &grant_type ne password
    and &grant_type ne sas_services
  )
  ,mac=&sysmacroname
  ,msg=%str(Invalid value for grant_type: &grant_type)
)
%mp_abort(iftrue=(%mf_isblank(&path)=1)
  ,mac=&sysmacroname
  ,msg=%str(path value must be provided)
)
%mp_abort(iftrue=(%length(&path)=1)
  ,mac=&sysmacroname
  ,msg=%str(path value must be provided)
)
%mp_abort(iftrue=(%mf_isblank(&name)=1)
  ,mac=&sysmacroname
  ,msg=%str(name value must be provided)
)
options noquotelenmax;
* remove any trailing slash ;
%if "%substr(&path,%length(&path),1)" = "/" %then
  %let path=%substr(&path,1,%length(&path)-1);
/* ensure folder exists */
%put &sysmacroname: Path &path being checked / created;
%mv_createfolder(path=&path)
%local base_uri; /* location of rest apis */
%let base_uri=%mf_getplatform(VIYARESTAPI);
/* fetching folder details for provided path */
%local fname1;
%let fname1=%mf_getuniquefileref();
proc http method='GET' out=&fname1 &oauth_bearer
  url="&base_uri/folders/folders/@item?path=&path";
%if &grant_type=authorization_code %then %do;
  headers "Authorization"="Bearer &&&access_token_var";
%end;
run;
%if &debug %then %do;
  data _null_;
    infile &fname1;
    input;
    putlog _infile_;
  run;
%end;
%mp_abort(iftrue=(&SYS_PROCHTTP_STATUS_CODE ne 200)
  ,mac=&sysmacroname
  ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
)
/* path exists. Grab follow on link to check members */
%local libref1;
%let libref1=%mf_getuniquelibref();
libname &libref1 JSON fileref=&fname1;
data _null_;
  set &libref1..links;
  if rel='members' then call symputx('membercheck',quote("&base_uri"!!trim(href)),'l');
  else if rel='self' then call symputx('parentFolderUri',href,'l');
run;
data _null_;
  set &libref1..root;
  call symputx('folderid',id,'l');
run;
%local fname2;
%let fname2=%mf_getuniquefileref();
proc http method='GET'
    out=&fname2
    &oauth_bearer
    url=%unquote(%superq(membercheck));
    headers
  %if &grant_type=authorization_code %then %do;
            "Authorization"="Bearer &&&access_token_var"
  %end;
            'Accept'='application/vnd.sas.collection+json'
            'Accept-Language'='string';
%if &debug=1 %then %do;
   debug level = 3;
%end;
run;
/*data _null_;infile &fname2;input;putlog _infile_;run;*/
%mp_abort(iftrue=(&SYS_PROCHTTP_STATUS_CODE ne 200)
  ,mac=&sysmacroname
  ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
)
%if %upcase(&replace)=YES %then %do;
  %mv_deletejes(path=&path, name=&name)
%end;
%else %do;
  /* check that job does not already exist in that folder */
  %local libref2;
  %let libref2=%mf_getuniquelibref();
  libname &libref2 JSON fileref=&fname2;
  %local exists; %let exists=0;
  data _null_;
    set &libref2..items;
    if contenttype='jobDefinition' and upcase(name)="%upcase(&name)" then
      call symputx('exists',1,'l');
  run;
  %mp_abort(iftrue=(&exists=1)
    ,mac=&sysmacroname
    ,msg=%str(Job &name already exists in &path)
  )
  libname &libref2 clear;
%end;
/* set up the body of the request to create the service */
%local fname3;
%let fname3=%mf_getuniquefileref();
data _null_;
  file &fname3 TERMSTR=' ';
  length string $32767;
  string=cats('{"version": 0,"name":"'
  	,"&name"
  	,'","type":"Compute","parameters":[{"name":"_addjesbeginendmacros"'
    ,',"type":"CHARACTER","defaultValue":"false"}');
  context=quote(cats(symget('contextname')));
  if context ne '""' then do;
    string=cats(string,',{"version": 1,"name": "_contextName","defaultValue":'
     ,context,',"type":"CHARACTER","label":"Context Name","required": false}');
  end;
  string=cats(string,'],"code":"');
  put string;
run;
filename sasjs temp lrecl=3000;
data _null_;
  file sasjs;
  put "/* Created on %sysfunc(datetime(),datetime19.) by &sysuserid */";
/* WEBOUT BEGIN */
  put ' ';
  put '%macro mp_jsonout(action,ds,jref=_webout,dslabel=,fmt=Y,engine=PROCJSON,dbg=0 ';
  put ')/*/STORE SOURCE*/; ';
  put '%put output location=&jref; ';
  put '%if &action=OPEN %then %do; ';
  put '  data _null_;file &jref encoding=''utf-8''; ';
  put '    put ''{"START_DTTM" : "'' "%sysfunc(datetime(),datetime20.3)" ''"''; ';
  put '  run; ';
  put '%end; ';
  put '%else %if (&action=ARR or &action=OBJ) %then %do; ';
  put '  options validvarname=upcase; ';
  put '  data _null_;file &jref mod encoding=''utf-8''; ';
  put '    put ", ""%lowcase(%sysfunc(coalescec(&dslabel,&ds)))"":"; ';
  put ' ';
  put '  %if &engine=PROCJSON %then %do; ';
  put '    data;run;%let tempds=&syslast; ';
  put '    proc sql;drop table &tempds; ';
  put '    data &tempds /view=&tempds;set &ds; ';
  put '    %if &fmt=N %then format _numeric_ best32.;; ';
  put '    proc json out=&jref pretty ';
  put '        %if &action=ARR %then nokeys ; ';
  put '        ;export &tempds / nosastags fmtnumeric; ';
  put '    run; ';
  put '    proc sql;drop view &tempds; ';
  put '  %end; ';
  put '  %else %if &engine=DATASTEP %then %do; ';
  put '    %local cols i tempds; ';
  put '    %let cols=0; ';
  put '    %if %sysfunc(exist(&ds)) ne 1 & %sysfunc(exist(&ds,VIEW)) ne 1 %then %do; ';
  put '      %put &sysmacroname:  &ds NOT FOUND!!!; ';
  put '      %return; ';
  put '    %end; ';
  put '    data _null_;file &jref mod ; ';
  put '      put "["; call symputx(''cols'',0,''l''); ';
  put '    proc sort data=sashelp.vcolumn(where=(libname=''WORK'' & memname="%upcase(&ds)")) ';
  put '      out=_data_; ';
  put '      by varnum; ';
  put ' ';
  put '    data _null_; ';
  put '      set _last_ end=last; ';
  put '      call symputx(cats(''name'',_n_),name,''l''); ';
  put '      call symputx(cats(''type'',_n_),type,''l''); ';
  put '      call symputx(cats(''len'',_n_),length,''l''); ';
  put '      if last then call symputx(''cols'',_n_,''l''); ';
  put '    run; ';
  put ' ';
  put '    proc format; /* credit yabwon for special null removal */ ';
  put '      value bart ._ - .z = null ';
  put '      other = [best.]; ';
  put ' ';
  put '    data;run; %let tempds=&syslast; /* temp table for spesh char management */ ';
  put '    proc sql; drop table &tempds; ';
  put '    data &tempds/view=&tempds; ';
  put '      attrib _all_ label=''''; ';
  put '      %do i=1 %to &cols; ';
  put '        %if &&type&i=char %then %do; ';
  put '          length &&name&i $32767; ';
  put '          format &&name&i $32767.; ';
  put '        %end; ';
  put '      %end; ';
  put '      set &ds; ';
  put '      format _numeric_ bart.; ';
  put '    %do i=1 %to &cols; ';
  put '      %if &&type&i=char %then %do; ';
  put '        &&name&i=''"''!!trim(prxchange(''s/"/\"/'',-1, ';
  put '                    prxchange(''s/''!!''0A''x!!''/\n/'',-1, ';
  put '                    prxchange(''s/''!!''0D''x!!''/\r/'',-1, ';
  put '                    prxchange(''s/''!!''09''x!!''/\t/'',-1, ';
  put '                    prxchange(''s/\\/\\\\/'',-1,&&name&i) ';
  put '        )))))!!''"''; ';
  put '      %end; ';
  put '    %end; ';
  put '    run; ';
  put '    /* write to temp loc to avoid _webout truncation - https://support.sas.com/kb/49/325.html */ ';
  put '    filename _sjs temp lrecl=131068 encoding=''utf-8''; ';
  put '    data _null_; file _sjs lrecl=131068 encoding=''utf-8'' mod; ';
  put '      set &tempds; ';
  put '      if _n_>1 then put "," @; put ';
  put '      %if &action=ARR %then "[" ; %else "{" ; ';
  put '      %do i=1 %to &cols; ';
  put '        %if &i>1 %then  "," ; ';
  put '        %if &action=OBJ %then """&&name&i"":" ; ';
  put '        &&name&i ';
  put '      %end; ';
  put '      %if &action=ARR %then "]" ; %else "}" ; ; ';
  put '    proc sql; ';
  put '    drop view &tempds; ';
  put '    /* now write the long strings to _webout 1 byte at a time */ ';
  put '    data _null_; ';
  put '      length filein 8 fileid 8; ';
  put '      filein = fopen("_sjs",''I'',1,''B''); ';
  put '      fileid = fopen("&jref",''A'',1,''B''); ';
  put '      rec = ''20''x; ';
  put '      do while(fread(filein)=0); ';
  put '        rc = fget(filein,rec,1); ';
  put '        rc = fput(fileid, rec); ';
  put '        rc =fwrite(fileid); ';
  put '      end; ';
  put '      rc = fclose(filein); ';
  put '      rc = fclose(fileid); ';
  put '    run; ';
  put '    filename _sjs clear; ';
  put '    data _null_; file &jref mod encoding=''utf-8''; ';
  put '      put "]"; ';
  put '    run; ';
  put '  %end; ';
  put '%end; ';
  put ' ';
  put '%else %if &action=CLOSE %then %do; ';
  put '  data _null_;file &jref encoding=''utf-8''; ';
  put '    put "}"; ';
  put '  run; ';
  put '%end; ';
  put '%mend; ';
  put '%macro mv_webout(action,ds,fref=_mvwtemp,dslabel=,fmt=Y); ';
  put '%global _webin_file_count _webin_fileuri _debug _omittextlog _webin_name ';
  put '  sasjs_tables SYS_JES_JOB_URI; ';
  put '%if %index("&_debug",log) %then %let _debug=131; ';
  put ' ';
  put '%local i tempds; ';
  put '%let action=%upcase(&action); ';
  put ' ';
  put '%if &action=FETCH %then %do; ';
  put '  %if %upcase(&_omittextlog)=FALSE or %str(&_debug) ge 131 %then %do; ';
  put '    options mprint notes mprintnest; ';
  put '  %end; ';
  put ' ';
  put '  %if not %symexist(_webin_fileuri1) %then %do; ';
  put '    %let _webin_file_count=%eval(&_webin_file_count+0); ';
  put '    %let _webin_fileuri1=&_webin_fileuri; ';
  put '    %let _webin_name1=&_webin_name; ';
  put '  %end; ';
  put ' ';
  put '  /* if the sasjs_tables param is passed, we expect param based upload */ ';
  put '  %if %length(&sasjs_tables.XX)>2 %then %do; ';
  put '    filename _sasjs "%sysfunc(pathname(work))/sasjs.lua"; ';
  put '    data _null_; ';
  put '      file _sasjs; ';
  put '      put ''s=sas.symget("sasjs_tables")''; ';
  put '      put ''if(s:sub(1,7) == "%nrstr(")''; ';
  put '      put ''then''; ';
  put '      put '' tablist=s:sub(8,s:len()-1)''; ';
  put '      put ''else''; ';
  put '      put '' tablist=s''; ';
  put '      put ''end''; ';
  put '      put ''for i = 1,sas.countw(tablist) ''; ';
  put '      put ''do ''; ';
  put '      put ''  tab=sas.scan(tablist,i)''; ';
  put '      put ''  sasdata=""''; ';
  put '      put ''  if (sas.symexist("sasjs"..i.."data0")==0)''; ';
  put '      put ''  then''; ';
  put '      /* TODO - condense this logic */ ';
  put '      put ''    s=sas.symget("sasjs"..i.."data")''; ';
  put '      put ''    if(s:sub(1,7) == "%nrstr(")''; ';
  put '      put ''    then''; ';
  put '      put ''      sasdata=s:sub(8,s:len()-1)''; ';
  put '      put ''    else''; ';
  put '      put ''      sasdata=s''; ';
  put '      put ''    end''; ';
  put '      put ''  else''; ';
  put '      put ''    for d = 1, sas.symget("sasjs"..i.."data0")''; ';
  put '      put ''    do''; ';
  put '      put ''      s=sas.symget("sasjs"..i.."data"..d)''; ';
  put '      put ''      if(s:sub(1,7) == "%nrstr(")''; ';
  put '      put ''      then''; ';
  put '      put ''        sasdata=sasdata..s:sub(8,s:len()-1)''; ';
  put '      put ''      else''; ';
  put '      put ''        sasdata=sasdata..s''; ';
  put '      put ''      end''; ';
  put '      put ''    end''; ';
  put '      put ''  end''; ';
  put '      put ''  file = io.open(sas.pathname("work").."/"..tab..".csv", "a")''; ';
  put '      put ''  io.output(file)''; ';
  put '      put ''  io.write(sasdata)''; ';
  put '      put ''  io.close(file)''; ';
  put '      put ''end''; ';
  put '    run; ';
  put '    %inc _sasjs; ';
  put ' ';
  put '    /* now read in the data */ ';
  put '    %do i=1 %to %sysfunc(countw(&sasjs_tables)); ';
  put '      %local table; %let table=%scan(&sasjs_tables,&i); ';
  put '      data _null_; ';
  put '        infile "%sysfunc(pathname(work))/&table..csv" termstr=crlf ; ';
  put '        input; ';
  put '        if _n_=1 then call symputx(''input_statement'',_infile_); ';
  put '        list; ';
  put '      data &table; ';
  put '        infile "%sysfunc(pathname(work))/&table..csv" firstobs=2 dsd termstr=crlf; ';
  put '        input &input_statement; ';
  put '      run; ';
  put '    %end; ';
  put '  %end; ';
  put '  %else %do i=1 %to &_webin_file_count; ';
  put '    /* read in any files that are sent */ ';
  put '    /* this part needs refactoring for wide files */ ';
  put '    filename indata filesrvc "&&_webin_fileuri&i" lrecl=999999; ';
  put '    data _null_; ';
  put '      infile indata termstr=crlf lrecl=32767; ';
  put '      input; ';
  put '      if _n_=1 then call symputx(''input_statement'',_infile_); ';
  put '      %if %str(&_debug) ge 131 %then %do; ';
  put '        if _n_<20 then putlog _infile_; ';
  put '        else stop; ';
  put '      %end; ';
  put '      %else %do; ';
  put '        stop; ';
  put '      %end; ';
  put '    run; ';
  put '    data &&_webin_name&i; ';
  put '      infile indata firstobs=2 dsd termstr=crlf ; ';
  put '      input &input_statement; ';
  put '    run; ';
  put '    %let sasjs_tables=&sasjs_tables &&_webin_name&i; ';
  put '  %end; ';
  put '%end; ';
  put '%else %if &action=OPEN %then %do; ';
  put '  /* setup webout */ ';
  put '  OPTIONS NOBOMFILE; ';
  put '  %if "X&SYS_JES_JOB_URI.X"="XX" %then %do; ';
  put '     filename _webout temp lrecl=999999 mod; ';
  put '  %end; ';
  put '  %else %do; ';
  put '    filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" ';
  put '      name="_webout.json" lrecl=999999 mod; ';
  put '  %end; ';
  put ' ';
  put '  /* setup temp ref */ ';
  put '  %if %upcase(&fref) ne _WEBOUT %then %do; ';
  put '    filename &fref temp lrecl=999999 permission=''A::u::rwx,A::g::rw-,A::o::---'' mod; ';
  put '  %end; ';
  put ' ';
  put '  /* setup json */ ';
  put '  data _null_;file &fref; ';
  put '    put ''{"START_DTTM" : "'' "%sysfunc(datetime(),datetime20.3)" ''"''; ';
  put '  run; ';
  put '%end; ';
  put '%else %if &action=ARR or &action=OBJ %then %do; ';
  put '    %mp_jsonout(&action,&ds,dslabel=&dslabel,fmt=&fmt ';
  put '      ,jref=&fref,engine=PROCJSON,dbg=%str(&_debug) ';
  put '    ) ';
  put '%end; ';
  put '%else %if &action=CLOSE %then %do; ';
  put '  %if %str(&_debug) ge 131 %then %do; ';
  put '    /* send back first 10 records of each work table for debugging */ ';
  put '    options obs=10; ';
  put '    data;run;%let tempds=%scan(&syslast,2,.); ';
  put '    ods output Members=&tempds; ';
  put '    proc datasets library=WORK memtype=data; ';
  put '    %local wtcnt;%let wtcnt=0; ';
  put '    data _null_; set &tempds; ';
  put '      if not (name =:"DATA"); ';
  put '      i+1; ';
  put '      call symputx(''wt''!!left(i),name); ';
  put '      call symputx(''wtcnt'',i); ';
  put '    data _null_; file &fref mod; put ",""WORK"":{"; ';
  put '    %do i=1 %to &wtcnt; ';
  put '      %let wt=&&wt&i; ';
  put '      proc contents noprint data=&wt ';
  put '        out=_data_ (keep=name type length format:); ';
  put '      run;%let tempds=%scan(&syslast,2,.); ';
  put '      data _null_; file &fref mod; ';
  put '        dsid=open("WORK.&wt",''is''); ';
  put '        nlobs=attrn(dsid,''NLOBS''); ';
  put '        nvars=attrn(dsid,''NVARS''); ';
  put '        rc=close(dsid); ';
  put '        if &i>1 then put '',''@; ';
  put '        put " ""&wt"" : {"; ';
  put '        put ''"nlobs":'' nlobs; ';
  put '        put '',"nvars":'' nvars; ';
  put '      %mp_jsonout(OBJ,&tempds,jref=&fref,dslabel=colattrs,engine=DATASTEP) ';
  put '      %mp_jsonout(OBJ,&wt,jref=&fref,dslabel=first10rows,engine=DATASTEP) ';
  put '      data _null_; file &fref mod;put "}"; ';
  put '    %end; ';
  put '    data _null_; file &fref mod;put "}";run; ';
  put '  %end; ';
  put ' ';
  put '  /* close off json */ ';
  put '  data _null_;file &fref mod; ';
  put '    _PROGRAM=quote(trim(resolve(symget(''_PROGRAM'')))); ';
  put '    put ",""SYSUSERID"" : ""&sysuserid"" "; ';
  put '    put ",""MF_GETUSER"" : ""%mf_getuser()"" "; ';
  put '    SYS_JES_JOB_URI=quote(trim(resolve(symget(''SYS_JES_JOB_URI'')))); ';
  put '    put '',"SYS_JES_JOB_URI" : '' SYS_JES_JOB_URI ; ';
  put '    put ",""SYSJOBID"" : ""&sysjobid"" "; ';
  put '    put ",""_DEBUG"" : ""&_debug"" "; ';
  put '    put '',"_PROGRAM" : '' _PROGRAM ; ';
  put '    put ",""SYSCC"" : ""&syscc"" "; ';
  put '    put ",""SYSERRORTEXT"" : ""&syserrortext"" "; ';
  put '    put ",""SYSHOSTNAME"" : ""&syshostname"" "; ';
  put '    put ",""SYSSITE"" : ""&syssite"" "; ';
  put '    put ",""SYSWARNINGTEXT"" : ""&syswarningtext"" "; ';
  put '    put '',"END_DTTM" : "'' "%sysfunc(datetime(),datetime20.3)" ''" ''; ';
  put '    put "}"; ';
  put ' ';
  put '  %if %upcase(&fref) ne _WEBOUT %then %do; ';
  put '    data _null_; rc=fcopy("&fref","_webout");run; ';
  put '  %end; ';
  put ' ';
  put '%end; ';
  put ' ';
  put '%mend; ';
  put ' ';
  put '%macro mf_getuser(type=META ';
  put ')/*/STORE SOURCE*/; ';
  put '  %local user metavar; ';
  put '  %if &type=OS %then %let metavar=_secureusername; ';
  put '  %else %let metavar=_metaperson; ';
  put ' ';
  put '  %if %symexist(SYS_COMPUTE_SESSION_OWNER) %then %let user=&SYS_COMPUTE_SESSION_OWNER; ';
  put '  %else %if %symexist(&metavar) %then %do; ';
  put '    %if %length(&&&metavar)=0 %then %let user=&sysuserid; ';
  put '    /* sometimes SAS will add @domain extension - remove for consistency */ ';
  put '    %else %let user=%scan(&&&metavar,1,@); ';
  put '  %end; ';
  put '  %else %let user=&sysuserid; ';
  put ' ';
  put '  %quote(&user) ';
  put ' ';
  put '%mend; ';
/* WEBOUT END */
  put '/* if calling viya service with _job param, _program will conflict */';
  put '/* so it is provided by SASjs instead as __program */';
  put '%global __program _program;';
  put '%let _program=%sysfunc(coalescec(&__program,&_program));';
  put ' ';
  put '%macro webout(action,ds,dslabel=,fmt=);';
  put '  %mv_webout(&action,ds=&ds,dslabel=&dslabel,fmt=&fmt)';
  put '%mend;';
run;
/* insert the code, escaping double quotes and carriage returns */
%local x fref freflist;
%let freflist= &adapter &precode &code ;
%do x=1 %to %sysfunc(countw(&freflist));
  %let fref=%scan(&freflist,&x);
  %put &sysmacroname: adding &fref;
  data _null_;
    length filein 8 fileid 8;
    filein = fopen("&fref","I",1,"B");
    fileid = fopen("&fname3","A",1,"B");
    rec = "20"x;
    do while(fread(filein)=0);
      rc = fget(filein,rec,1);
      if rec='"' then do;
        rc =fput(fileid,'\');rc =fwrite(fileid);
        rc =fput(fileid,'"');rc =fwrite(fileid);
      end;
      else if rec='0A'x then do;
        rc =fput(fileid,'\');rc =fwrite(fileid);
        rc =fput(fileid,'r');rc =fwrite(fileid);
      end;
      else if rec='0D'x then do;
        rc =fput(fileid,'\');rc =fwrite(fileid);
        rc =fput(fileid,'n');rc =fwrite(fileid);
      end;
      else if rec='09'x then do;
        rc =fput(fileid,'\');rc =fwrite(fileid);
        rc =fput(fileid,'t');rc =fwrite(fileid);
      end;
      else if rec='5C'x then do;
        rc =fput(fileid,'\');rc =fwrite(fileid);
        rc =fput(fileid,'\');rc =fwrite(fileid);
      end;
      else do;
        rc =fput(fileid,rec);
        rc =fwrite(fileid);
      end;
    end;
    rc=fclose(filein);
    rc=fclose(fileid);
  run;
%end;
/* finish off the body of the code file loaded to JES */
data _null_;
  file &fname3 mod TERMSTR=' ';
  put '"}';
run;
/* now we can create the job!! */
%local fname4;
%let fname4=%mf_getuniquefileref();
proc http method='POST'
    in=&fname3
    out=&fname4
    &oauth_bearer
    url="&base_uri/jobDefinitions/definitions?parentFolderUri=&parentFolderUri";
    headers 'Content-Type'='application/vnd.sas.job.definition+json'
  %if &grant_type=authorization_code %then %do;
            "Authorization"="Bearer &&&access_token_var"
  %end;
            "Accept"="application/vnd.sas.job.definition+json";
%if &debug=1 %then %do;
   debug level = 3;
%end;
run;
/*data _null_;infile &fname4;input;putlog _infile_;run;*/
%mp_abort(iftrue=(&SYS_PROCHTTP_STATUS_CODE ne 201)
  ,mac=&sysmacroname
  ,msg=%str(&SYS_PROCHTTP_STATUS_CODE &SYS_PROCHTTP_STATUS_PHRASE)
)
/* clear refs */
filename &fname1 clear;
filename &fname2 clear;
filename &fname3 clear;
filename &fname4 clear;
filename &adapter clear;
libname &libref1 clear;
/* get the url so we can give a helpful log message */
%local url;
data _null_;
  if symexist('_baseurl') then do;
    url=symget('_baseurl');
    if subpad(url,length(url)-9,9)='SASStudio'
      then url=substr(url,1,length(url)-11);
    else url="&systcpiphostname";
  end;
  else url="&systcpiphostname";
  call symputx('url',url);
run;
%put &sysmacroname: Job &name successfully created in &path;
%put &sysmacroname:;
%put &sysmacroname: Check it out here:;
%put &sysmacroname:;%put;
%put    &url/SASJobExecution?_PROGRAM=&path/&name;%put;
%put &sysmacroname:;
%put &sysmacroname:;
%mend;
%let path=;
%let service=clickme;
filename sascode temp lrecl=32767;
data _null_;
file sascode;
 put '%macro sasjsout(type,fref=sasjs);';
 put '%global sysprocessmode SYS_JES_JOB_URI;';
 put '%if "&sysprocessmode"="SAS Compute Server" %then %do;';
 put '%if &type=HTML %then %do;';
 put 'filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" name="_webout.json"';
 put 'contenttype="text/html";';
 put '%end;';
 put '%else %if &type=JS or &type=JS64 %then %do;';
 put 'filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" name=''_webout.js''';
 put 'contenttype=''application/javascript'';';
 put '%end;';
 put '%else %if &type=CSS or &type=CSS64 %then %do;';
 put 'filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" name=''_webout.css''';
 put 'contenttype=''text/css'';';
 put '%end;';
 put '%else %if &type=PNG %then %do;';
 put 'filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" name=''_webout.png''';
 put 'contenttype=''image/png'' lrecl=2000000 recfm=n;';
 put '%end;';
 put '%else %if &type=JSON %then %do;';
 put 'filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" name=''_webout.json''';
 put 'contenttype=''application/json'' lrecl=2000000 recfm=n;';
 put '%end;';
 put '%else %if &type=MP3 %then %do;';
 put 'filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" name=''_webout.mp3''';
 put 'contenttype=''audio/mpeg'' lrecl=2000000 recfm=n;';
 put '%end;';
 put '%end;';
 put '%else %do;';
 put '%if &type=JS or &type=JS64 %then %do;';
 put '%let rc=%sysfunc(stpsrv_header(Content-type,application/javascript));';
 put '%end;';
 put '%else %if &type=CSS or &type=CSS64 %then %do;';
 put '%let rc=%sysfunc(stpsrv_header(Content-type,text/css));';
 put '%end;';
 put '%else %if &type=PNG %then %do;';
 put '%let rc=%sysfunc(stpsrv_header(Content-type,image/png));';
 put '%end;';
 put '%else %if &type=JSON %then %do;';
 put '%let rc=%sysfunc(stpsrv_header(Content-type,application/json));';
 put '%end;';
 put '%else %if &type=MP3 %then %do;';
 put '%let rc=%sysfunc(stpsrv_header(Content-type,audio/mpeg));';
 put '%end;';
 put '%end;';
 put '%if &type=HTML %then %do;';
 put '/*';
 put 'We need to perform some substitutions -eg to get the APPLOC and SERVERTYPE.';
 put 'Therefore the developer should avoid writing lines that exceed 32k';
 put 'characters (eg base64 encoded images) as they will get truncated when passing';
 put 'through the datastep.  This could of course be re-written using LUA, removing';
 put 'the length restriction.  Pull requests are welcome!';
 put '*/';
 put 'filename _sjs temp;';
 put 'data _null_;';
 put 'file _sjs lrecl=32767 encoding=''utf-8'';';
 put 'infile &fref lrecl=32767;';
 put 'input;';
 put 'if find(_infile_,'' appLoc: '') then do;';
 put 'pgm="&_program";';
 put 'rootlen=length(trim(pgm))-length(scan(pgm,-1,''/''))-1;';
 put 'root=quote(substr(pgm,1,rootlen));';
 put 'put ''    appLoc: '' root '','';';
 put 'end;';
 put 'else if find(_infile_,'' serverType: '') then do;';
 put 'if symexist(''_metaperson'') then put ''    serverType: "SAS9" ,'';';
 put 'else put ''    serverType: "SASVIYA" ,'';';
 put 'end;';
 put 'else if find(_infile_,'' hostUrl: '') then do;';
 put '/* nothing - we are streaming so this will default to hostname */';
 put 'end;';
 put 'else put _infile_;';
 put 'run;';
 put '%let fref=_sjs;';
 put '%end;';
 put '/* stream byte by byte */';
 put '/* in SAS9, JS & CSS files are base64 encoded to avoid UTF8 issues in WLATIN1 metadata */';
 put '%if &type=PNG or &type=MP3 or &type=JS64 or &type=CSS64 %then %do;';
 put 'data _null_;';
 put 'length filein 8 fileout 8;';
 put 'filein = fopen("&fref",''I'',4,''B'');';
 put 'fileout = fopen("_webout",''A'',1,''B'');';
 put 'char= ''20''x;';
 put 'do while(fread(filein)=0);';
 put 'raw="1234";';
 put 'do i=1 to 4;';
 put 'rc=fget(filein,char,1);';
 put 'substr(raw,i,1)=char;';
 put 'end;';
 put 'val="123";';
 put 'val=input(raw,$base64X4.);';
 put 'do i=1 to 3;';
 put 'length byte $1;';
 put 'byte=byte(rank(substr(val,i,1)));';
 put 'rc = fput(fileout, byte);';
 put 'end;';
 put 'rc =fwrite(fileout);';
 put 'end;';
 put 'rc = fclose(filein);';
 put 'rc = fclose(fileout);';
 put 'run;';
 put '%end;';
 put '%else %do;';
 put 'data _null_;';
 put 'length filein 8 fileid 8;';
 put 'filein = fopen("&fref",''I'',1,''B'');';
 put 'fileid = fopen("_webout",''A'',1,''B'');';
 put 'rec = ''20''x;';
 put 'do while(fread(filein)=0);';
 put 'rc = fget(filein,rec,1);';
 put 'rc = fput(fileid, rec);';
 put 'rc =fwrite(fileid);';
 put 'end;';
 put 'rc = fclose(filein);';
 put 'rc = fclose(fileid);';
 put 'run;';
 put '%end;';
 put '%mend;';
 put 'filename sasjs temp lrecl=99999999;';
 put 'data _null_;';
 put 'file sasjs;';
 put 'put ''<!DOCTYPE html><html lang="en"><head>'';';
 put 'put ''  <meta charset="utf-8">'';';
 put 'put '' '';';
 put 'put ''  <title>Log Parser</title>'';';
 put 'put ''  <meta name="description" content="The SASjs Viya Log Parser">'';';
 put 'put '' '';';
 put 'put ''  <!-- uncomment this for better styling'';';
 put 'put ''    <link rel="stylesheet" href="https://unpkg.com/@clr/ui/clr-ui.min.css" />'';';
 put 'put ''-->'';';
 put 'put '' '';';
 put 'put ''</head>'';';
 put 'put '' '';';
 put 'put ''<body style="padding: 20px">'';';
 put 'put ''  <h1>Log Parser</h1>'';';
 put 'put '' '';';
 put 'put ''  <textarea id="log_text" style="width: 100%; height: 200px;" placeholder="Paste Viya log in json format to parse as plain text"></textarea>'';';
 put 'put '' '';';
 put 'put ''  <button onclick="parseLogLines()" type="button" class="btn btn-primary">Parse log</button>'';';
 put 'put '' '';';
 put 'put ''  <div id="result">'';';
 put 'put ''    <h2>Plain text log</h2>'';';
 put 'put ''    <pre id="log_result" style="padding: 5px;">No log parsed yet.</pre>'';';
 put 'put ''  </div>'';';
 put 'put '' '';';
 put 'put ''  <script src="/SASJobExecution?_PROGRAM=/Public/sasjs/log-parser/webv/mainjs"></script>'';';
 put 'put '' '';';
 put 'put ''</body></html>'';';
 put 'run;';
 put '%sasjsout(HTML)';
run;
%mv_createwebservice(path=&appLoc/&path, name=&service, code=sascode ,replace=yes)
filename sascode clear;
%let path=common;
%let service=appinit;
filename sascode temp lrecl=32767;
data _null_;
file sascode;
 put '%macro mf_getuser(type=META';
 put ')/*/STORE SOURCE*/;';
 put '%local user metavar;';
 put '%if &type=OS %then %let metavar=_secureusername;';
 put '%else %let metavar=_metaperson;';
 put '%if %symexist(SYS_COMPUTE_SESSION_OWNER) %then %let user=&SYS_COMPUTE_SESSION_OWNER;';
 put '%else %if %symexist(&metavar) %then %do;';
 put '%if %length(&&&metavar)=0 %then %let user=&sysuserid;';
 put '/* sometimes SAS will add @domain extension - remove for consistency */';
 put '%else %let user=%scan(&&&metavar,1,@);';
 put '%end;';
 put '%else %let user=&sysuserid;';
 put '%quote(&user)';
 put '%mend;';
 put '%macro mp_jsonout(action,ds,jref=_webout,dslabel=,fmt=Y,engine=PROCJSON,dbg=0';
 put ')/*/STORE SOURCE*/;';
 put '%put output location=&jref;';
 put '%if &action=OPEN %then %do;';
 put 'data _null_;file &jref encoding=''utf-8'';';
 put 'put ''{"START_DTTM" : "'' "%sysfunc(datetime(),datetime20.3)" ''"'';';
 put 'run;';
 put '%end;';
 put '%else %if (&action=ARR or &action=OBJ) %then %do;';
 put 'options validvarname=upcase;';
 put 'data _null_;file &jref mod encoding=''utf-8'';';
 put 'put ", ""%lowcase(%sysfunc(coalescec(&dslabel,&ds)))"":";';
 put '%if &engine=PROCJSON %then %do;';
 put 'data;run;%let tempds=&syslast;';
 put 'proc sql;drop table &tempds;';
 put 'data &tempds /view=&tempds;set &ds;';
 put '%if &fmt=N %then format _numeric_ best32.;;';
 put 'proc json out=&jref pretty';
 put '%if &action=ARR %then nokeys ;';
 put ';export &tempds / nosastags fmtnumeric;';
 put 'run;';
 put 'proc sql;drop view &tempds;';
 put '%end;';
 put '%else %if &engine=DATASTEP %then %do;';
 put '%local cols i tempds;';
 put '%let cols=0;';
 put '%if %sysfunc(exist(&ds)) ne 1 & %sysfunc(exist(&ds,VIEW)) ne 1 %then %do;';
 put '%put &sysmacroname:  &ds NOT FOUND!!!;';
 put '%return;';
 put '%end;';
 put 'data _null_;file &jref mod ;';
 put 'put "["; call symputx(''cols'',0,''l'');';
 put 'proc sort data=sashelp.vcolumn(where=(libname=''WORK'' & memname="%upcase(&ds)"))';
 put 'out=_data_;';
 put 'by varnum;';
 put 'data _null_;';
 put 'set _last_ end=last;';
 put 'call symputx(cats(''name'',_n_),name,''l'');';
 put 'call symputx(cats(''type'',_n_),type,''l'');';
 put 'call symputx(cats(''len'',_n_),length,''l'');';
 put 'if last then call symputx(''cols'',_n_,''l'');';
 put 'run;';
 put 'proc format; /* credit yabwon for special null removal */';
 put 'value bart ._ - .z = null';
 put 'other = [best.];';
 put 'data;run; %let tempds=&syslast; /* temp table for spesh char management */';
 put 'proc sql; drop table &tempds;';
 put 'data &tempds/view=&tempds;';
 put 'attrib _all_ label='''';';
 put '%do i=1 %to &cols;';
 put '%if &&type&i=char %then %do;';
 put 'length &&name&i $32767;';
 put 'format &&name&i $32767.;';
 put '%end;';
 put '%end;';
 put 'set &ds;';
 put 'format _numeric_ bart.;';
 put '%do i=1 %to &cols;';
 put '%if &&type&i=char %then %do;';
 put '&&name&i=''"''!!trim(prxchange(''s/"/\"/'',-1,';
 put 'prxchange(''s/''!!''0A''x!!''/\n/'',-1,';
 put 'prxchange(''s/''!!''0D''x!!''/\r/'',-1,';
 put 'prxchange(''s/''!!''09''x!!''/\t/'',-1,';
 put 'prxchange(''s/\\/\\\\/'',-1,&&name&i)';
 put ')))))!!''"'';';
 put '%end;';
 put '%end;';
 put 'run;';
 put '/* write to temp loc to avoid _webout truncation - https://support.sas.com/kb/49/325.html */';
 put 'filename _sjs temp lrecl=131068 encoding=''utf-8'';';
 put 'data _null_; file _sjs lrecl=131068 encoding=''utf-8'' mod;';
 put 'set &tempds;';
 put 'if _n_>1 then put "," @; put';
 put '%if &action=ARR %then "[" ; %else "{" ;';
 put '%do i=1 %to &cols;';
 put '%if &i>1 %then  "," ;';
 put '%if &action=OBJ %then """&&name&i"":" ;';
 put '&&name&i';
 put '%end;';
 put '%if &action=ARR %then "]" ; %else "}" ; ;';
 put 'proc sql;';
 put 'drop view &tempds;';
 put '/* now write the long strings to _webout 1 byte at a time */';
 put 'data _null_;';
 put 'length filein 8 fileid 8;';
 put 'filein = fopen("_sjs",''I'',1,''B'');';
 put 'fileid = fopen("&jref",''A'',1,''B'');';
 put 'rec = ''20''x;';
 put 'do while(fread(filein)=0);';
 put 'rc = fget(filein,rec,1);';
 put 'rc = fput(fileid, rec);';
 put 'rc =fwrite(fileid);';
 put 'end;';
 put 'rc = fclose(filein);';
 put 'rc = fclose(fileid);';
 put 'run;';
 put 'filename _sjs clear;';
 put 'data _null_; file &jref mod encoding=''utf-8'';';
 put 'put "]";';
 put 'run;';
 put '%end;';
 put '%end;';
 put '%else %if &action=CLOSE %then %do;';
 put 'data _null_;file &jref encoding=''utf-8'';';
 put 'put "}";';
 put 'run;';
 put '%end;';
 put '%mend;/**';
 put '@file mv_webout.sas';
 put '@brief Send data to/from the SAS Viya Job Execution Service';
 put '@details This macro should be added to the start of each Job Execution';
 put 'Service, **immediately** followed by a call to:';
 put '%mv_webout(FETCH)';
 put 'This will read all the input data and create same-named SAS datasets in the';
 put 'WORK library.  You can then insert your code, and send data back using the';
 put 'following syntax:';
 put 'data some datasets; * make some data ;';
 put 'retain some columns;';
 put 'run;';
 put '%mv_webout(OPEN)';
 put '%mv_webout(ARR,some)  * Array format, fast, suitable for large tables ;';
 put '%mv_webout(OBJ,datasets) * Object format, easier to work with ;';
 put '%mv_webout(CLOSE)';
 put '@param action Either OPEN, ARR, OBJ or CLOSE';
 put '@param ds The dataset to send back to the frontend';
 put '@param _webout= fileref for returning the json';
 put '@param fref= temp fref';
 put '@param dslabel= value to use instead of the real name for sending to JSON';
 put '@param fmt= change to N to strip formats from output';
 put '<h4> Dependencies </h4>';
 put '@li mp_jsonout.sas';
 put '@li mf_getuser.sas';
 put '@version Viya 3.3';
 put '@author Allan Bowe, source: https://github.com/sasjs/core';
 put '**/';
 put '%macro mv_webout(action,ds,fref=_mvwtemp,dslabel=,fmt=Y);';
 put '%global _webin_file_count _webin_fileuri _debug _omittextlog _webin_name';
 put 'sasjs_tables SYS_JES_JOB_URI;';
 put '%if %index("&_debug",log) %then %let _debug=131;';
 put '%local i tempds;';
 put '%let action=%upcase(&action);';
 put '%if &action=FETCH %then %do;';
 put '%if %upcase(&_omittextlog)=FALSE or %str(&_debug) ge 131 %then %do;';
 put 'options mprint notes mprintnest;';
 put '%end;';
 put '%if not %symexist(_webin_fileuri1) %then %do;';
 put '%let _webin_file_count=%eval(&_webin_file_count+0);';
 put '%let _webin_fileuri1=&_webin_fileuri;';
 put '%let _webin_name1=&_webin_name;';
 put '%end;';
 put '/* if the sasjs_tables param is passed, we expect param based upload */';
 put '%if %length(&sasjs_tables.XX)>2 %then %do;';
 put 'filename _sasjs "%sysfunc(pathname(work))/sasjs.lua";';
 put 'data _null_;';
 put 'file _sasjs;';
 put 'put ''s=sas.symget("sasjs_tables")'';';
 put 'put ''if(s:sub(1,7) == "%nrstr(")'';';
 put 'put ''then'';';
 put 'put '' tablist=s:sub(8,s:len()-1)'';';
 put 'put ''else'';';
 put 'put '' tablist=s'';';
 put 'put ''end'';';
 put 'put ''for i = 1,sas.countw(tablist) '';';
 put 'put ''do '';';
 put 'put ''  tab=sas.scan(tablist,i)'';';
 put 'put ''  sasdata=""'';';
 put 'put ''  if (sas.symexist("sasjs"..i.."data0")==0)'';';
 put 'put ''  then'';';
 put '/* TODO - condense this logic */';
 put 'put ''    s=sas.symget("sasjs"..i.."data")'';';
 put 'put ''    if(s:sub(1,7) == "%nrstr(")'';';
 put 'put ''    then'';';
 put 'put ''      sasdata=s:sub(8,s:len()-1)'';';
 put 'put ''    else'';';
 put 'put ''      sasdata=s'';';
 put 'put ''    end'';';
 put 'put ''  else'';';
 put 'put ''    for d = 1, sas.symget("sasjs"..i.."data0")'';';
 put 'put ''    do'';';
 put 'put ''      s=sas.symget("sasjs"..i.."data"..d)'';';
 put 'put ''      if(s:sub(1,7) == "%nrstr(")'';';
 put 'put ''      then'';';
 put 'put ''        sasdata=sasdata..s:sub(8,s:len()-1)'';';
 put 'put ''      else'';';
 put 'put ''        sasdata=sasdata..s'';';
 put 'put ''      end'';';
 put 'put ''    end'';';
 put 'put ''  end'';';
 put 'put ''  file = io.open(sas.pathname("work").."/"..tab..".csv", "a")'';';
 put 'put ''  io.output(file)'';';
 put 'put ''  io.write(sasdata)'';';
 put 'put ''  io.close(file)'';';
 put 'put ''end'';';
 put 'run;';
 put '%inc _sasjs;';
 put '/* now read in the data */';
 put '%do i=1 %to %sysfunc(countw(&sasjs_tables));';
 put '%local table; %let table=%scan(&sasjs_tables,&i);';
 put 'data _null_;';
 put 'infile "%sysfunc(pathname(work))/&table..csv" termstr=crlf ;';
 put 'input;';
 put 'if _n_=1 then call symputx(''input_statement'',_infile_);';
 put 'list;';
 put 'data &table;';
 put 'infile "%sysfunc(pathname(work))/&table..csv" firstobs=2 dsd termstr=crlf;';
 put 'input &input_statement;';
 put 'run;';
 put '%end;';
 put '%end;';
 put '%else %do i=1 %to &_webin_file_count;';
 put '/* read in any files that are sent */';
 put '/* this part needs refactoring for wide files */';
 put 'filename indata filesrvc "&&_webin_fileuri&i" lrecl=999999;';
 put 'data _null_;';
 put 'infile indata termstr=crlf lrecl=32767;';
 put 'input;';
 put 'if _n_=1 then call symputx(''input_statement'',_infile_);';
 put '%if %str(&_debug) ge 131 %then %do;';
 put 'if _n_<20 then putlog _infile_;';
 put 'else stop;';
 put '%end;';
 put '%else %do;';
 put 'stop;';
 put '%end;';
 put 'run;';
 put 'data &&_webin_name&i;';
 put 'infile indata firstobs=2 dsd termstr=crlf ;';
 put 'input &input_statement;';
 put 'run;';
 put '%let sasjs_tables=&sasjs_tables &&_webin_name&i;';
 put '%end;';
 put '%end;';
 put '%else %if &action=OPEN %then %do;';
 put '/* setup webout */';
 put 'OPTIONS NOBOMFILE;';
 put '%if "X&SYS_JES_JOB_URI.X"="XX" %then %do;';
 put 'filename _webout temp lrecl=999999 mod;';
 put '%end;';
 put '%else %do;';
 put 'filename _webout filesrvc parenturi="&SYS_JES_JOB_URI"';
 put 'name="_webout.json" lrecl=999999 mod;';
 put '%end;';
 put '/* setup temp ref */';
 put '%if %upcase(&fref) ne _WEBOUT %then %do;';
 put 'filename &fref temp lrecl=999999 permission=''A::u::rwx,A::g::rw-,A::o::---'' mod;';
 put '%end;';
 put '/* setup json */';
 put 'data _null_;file &fref;';
 put 'put ''{"START_DTTM" : "'' "%sysfunc(datetime(),datetime20.3)" ''"'';';
 put 'run;';
 put '%end;';
 put '%else %if &action=ARR or &action=OBJ %then %do;';
 put '%mp_jsonout(&action,&ds,dslabel=&dslabel,fmt=&fmt';
 put ',jref=&fref,engine=PROCJSON,dbg=%str(&_debug)';
 put ')';
 put '%end;';
 put '%else %if &action=CLOSE %then %do;';
 put '%if %str(&_debug) ge 131 %then %do;';
 put '/* send back first 10 records of each work table for debugging */';
 put 'options obs=10;';
 put 'data;run;%let tempds=%scan(&syslast,2,.);';
 put 'ods output Members=&tempds;';
 put 'proc datasets library=WORK memtype=data;';
 put '%local wtcnt;%let wtcnt=0;';
 put 'data _null_; set &tempds;';
 put 'if not (name =:"DATA");';
 put 'i+1;';
 put 'call symputx(''wt''!!left(i),name);';
 put 'call symputx(''wtcnt'',i);';
 put 'data _null_; file &fref mod; put ",""WORK"":{";';
 put '%do i=1 %to &wtcnt;';
 put '%let wt=&&wt&i;';
 put 'proc contents noprint data=&wt';
 put 'out=_data_ (keep=name type length format:);';
 put 'run;%let tempds=%scan(&syslast,2,.);';
 put 'data _null_; file &fref mod;';
 put 'dsid=open("WORK.&wt",''is'');';
 put 'nlobs=attrn(dsid,''NLOBS'');';
 put 'nvars=attrn(dsid,''NVARS'');';
 put 'rc=close(dsid);';
 put 'if &i>1 then put '',''@;';
 put 'put " ""&wt"" : {";';
 put 'put ''"nlobs":'' nlobs;';
 put 'put '',"nvars":'' nvars;';
 put '%mp_jsonout(OBJ,&tempds,jref=&fref,dslabel=colattrs,engine=DATASTEP)';
 put '%mp_jsonout(OBJ,&wt,jref=&fref,dslabel=first10rows,engine=DATASTEP)';
 put 'data _null_; file &fref mod;put "}";';
 put '%end;';
 put 'data _null_; file &fref mod;put "}";run;';
 put '%end;';
 put '/* close off json */';
 put 'data _null_;file &fref mod;';
 put '_PROGRAM=quote(trim(resolve(symget(''_PROGRAM''))));';
 put 'put ",""SYSUSERID"" : ""&sysuserid"" ";';
 put 'put ",""MF_GETUSER"" : ""%mf_getuser()"" ";';
 put 'SYS_JES_JOB_URI=quote(trim(resolve(symget(''SYS_JES_JOB_URI''))));';
 put 'put '',"SYS_JES_JOB_URI" : '' SYS_JES_JOB_URI ;';
 put 'put ",""SYSJOBID"" : ""&sysjobid"" ";';
 put 'put ",""_DEBUG"" : ""&_debug"" ";';
 put 'put '',"_PROGRAM" : '' _PROGRAM ;';
 put 'put ",""SYSCC"" : ""&syscc"" ";';
 put 'put ",""SYSERRORTEXT"" : ""&syserrortext"" ";';
 put 'put ",""SYSHOSTNAME"" : ""&syshostname"" ";';
 put 'put ",""SYSSITE"" : ""&syssite"" ";';
 put 'put ",""SYSWARNINGTEXT"" : ""&syswarningtext"" ";';
 put 'put '',"END_DTTM" : "'' "%sysfunc(datetime(),datetime20.3)" ''" '';';
 put 'put "}";';
 put '%if %upcase(&fref) ne _WEBOUT %then %do;';
 put 'data _null_; rc=fcopy("&fref","_webout");run;';
 put '%end;';
 put '%end;';
 put '%mend;';
 put '/* if calling viya service with _job param, _program will conflict */';
 put '/* so we provide instead as __program */';
 put '%global __program _program;';
 put '%let _program=%sysfunc(coalescec(&__program,&_program));';
 put '%macro webout(action,ds,dslabel=,fmt=);';
 put '%mv_webout(&action,ds=&ds,dslabel=&dslabel,fmt=&fmt)';
 put '%mend;';
 put '* Service Variables start;';
 put '*Service Variables end;';
 put '* Dependencies start;';
 put '* Dependencies end;';
 put '* Programs start;';
 put '*Programs end;';
 put '* Service start;';
 put '%put this is a dummy SAS Service;';
 put '* Service end;';
run;
%mv_createwebservice(path=&appLoc/&path, name=&service, code=sascode ,replace=yes)
filename sascode clear;
%let path=webv;
%let service=mainjs;
filename sascode temp lrecl=32767;
data _null_;
file sascode;
 put '%macro sasjsout(type,fref=sasjs);';
 put '%global sysprocessmode SYS_JES_JOB_URI;';
 put '%if "&sysprocessmode"="SAS Compute Server" %then %do;';
 put '%if &type=HTML %then %do;';
 put 'filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" name="_webout.json"';
 put 'contenttype="text/html";';
 put '%end;';
 put '%else %if &type=JS or &type=JS64 %then %do;';
 put 'filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" name=''_webout.js''';
 put 'contenttype=''application/javascript'';';
 put '%end;';
 put '%else %if &type=CSS or &type=CSS64 %then %do;';
 put 'filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" name=''_webout.css''';
 put 'contenttype=''text/css'';';
 put '%end;';
 put '%else %if &type=PNG %then %do;';
 put 'filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" name=''_webout.png''';
 put 'contenttype=''image/png'' lrecl=2000000 recfm=n;';
 put '%end;';
 put '%else %if &type=JSON %then %do;';
 put 'filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" name=''_webout.json''';
 put 'contenttype=''application/json'' lrecl=2000000 recfm=n;';
 put '%end;';
 put '%else %if &type=MP3 %then %do;';
 put 'filename _webout filesrvc parenturi="&SYS_JES_JOB_URI" name=''_webout.mp3''';
 put 'contenttype=''audio/mpeg'' lrecl=2000000 recfm=n;';
 put '%end;';
 put '%end;';
 put '%else %do;';
 put '%if &type=JS or &type=JS64 %then %do;';
 put '%let rc=%sysfunc(stpsrv_header(Content-type,application/javascript));';
 put '%end;';
 put '%else %if &type=CSS or &type=CSS64 %then %do;';
 put '%let rc=%sysfunc(stpsrv_header(Content-type,text/css));';
 put '%end;';
 put '%else %if &type=PNG %then %do;';
 put '%let rc=%sysfunc(stpsrv_header(Content-type,image/png));';
 put '%end;';
 put '%else %if &type=JSON %then %do;';
 put '%let rc=%sysfunc(stpsrv_header(Content-type,application/json));';
 put '%end;';
 put '%else %if &type=MP3 %then %do;';
 put '%let rc=%sysfunc(stpsrv_header(Content-type,audio/mpeg));';
 put '%end;';
 put '%end;';
 put '%if &type=HTML %then %do;';
 put '/*';
 put 'We need to perform some substitutions -eg to get the APPLOC and SERVERTYPE.';
 put 'Therefore the developer should avoid writing lines that exceed 32k';
 put 'characters (eg base64 encoded images) as they will get truncated when passing';
 put 'through the datastep.  This could of course be re-written using LUA, removing';
 put 'the length restriction.  Pull requests are welcome!';
 put '*/';
 put 'filename _sjs temp;';
 put 'data _null_;';
 put 'file _sjs lrecl=32767 encoding=''utf-8'';';
 put 'infile &fref lrecl=32767;';
 put 'input;';
 put 'if find(_infile_,'' appLoc: '') then do;';
 put 'pgm="&_program";';
 put 'rootlen=length(trim(pgm))-length(scan(pgm,-1,''/''))-1;';
 put 'root=quote(substr(pgm,1,rootlen));';
 put 'put ''    appLoc: '' root '','';';
 put 'end;';
 put 'else if find(_infile_,'' serverType: '') then do;';
 put 'if symexist(''_metaperson'') then put ''    serverType: "SAS9" ,'';';
 put 'else put ''    serverType: "SASVIYA" ,'';';
 put 'end;';
 put 'else if find(_infile_,'' hostUrl: '') then do;';
 put '/* nothing - we are streaming so this will default to hostname */';
 put 'end;';
 put 'else put _infile_;';
 put 'run;';
 put '%let fref=_sjs;';
 put '%end;';
 put '/* stream byte by byte */';
 put '/* in SAS9, JS & CSS files are base64 encoded to avoid UTF8 issues in WLATIN1 metadata */';
 put '%if &type=PNG or &type=MP3 or &type=JS64 or &type=CSS64 %then %do;';
 put 'data _null_;';
 put 'length filein 8 fileout 8;';
 put 'filein = fopen("&fref",''I'',4,''B'');';
 put 'fileout = fopen("_webout",''A'',1,''B'');';
 put 'char= ''20''x;';
 put 'do while(fread(filein)=0);';
 put 'raw="1234";';
 put 'do i=1 to 4;';
 put 'rc=fget(filein,char,1);';
 put 'substr(raw,i,1)=char;';
 put 'end;';
 put 'val="123";';
 put 'val=input(raw,$base64X4.);';
 put 'do i=1 to 3;';
 put 'length byte $1;';
 put 'byte=byte(rank(substr(val,i,1)));';
 put 'rc = fput(fileout, byte);';
 put 'end;';
 put 'rc =fwrite(fileout);';
 put 'end;';
 put 'rc = fclose(filein);';
 put 'rc = fclose(fileout);';
 put 'run;';
 put '%end;';
 put '%else %do;';
 put 'data _null_;';
 put 'length filein 8 fileid 8;';
 put 'filein = fopen("&fref",''I'',1,''B'');';
 put 'fileid = fopen("_webout",''A'',1,''B'');';
 put 'rec = ''20''x;';
 put 'do while(fread(filein)=0);';
 put 'rc = fget(filein,rec,1);';
 put 'rc = fput(fileid, rec);';
 put 'rc =fwrite(fileid);';
 put 'end;';
 put 'rc = fclose(filein);';
 put 'rc = fclose(fileid);';
 put 'run;';
 put '%end;';
 put '%mend;';
 put 'filename sasjs temp lrecl=99999999;';
 put 'data _null_;';
 put 'file sasjs;';
 put 'put ''const parseLogLines = () => {'';';
 put 'put ''  let logText = document.querySelector(''''#log_text'''').value'';';
 put 'put ''  let logJson = JSON.parse(logText)'';';
 put 'put ''  let logLines = '''''''''';';
 put 'put ''  for (let item of logJson.items) {'';';
 put 'put ''    logLines += `${item.line}\n`'';';
 put 'put ''  }'';';
 put 'put ''  let logResult = document.querySelector(''''#log_result'''').innerHTML = logLines'';';
 put 'put ''}'';';
 put 'run;';
 put '%sasjsout(JS)';
run;
%mv_createwebservice(path=&appLoc/&path, name=&service, code=sascode ,replace=yes)
filename sascode clear;