# Viya Log Parser

This is a simple utility for parsing Viya Log files from JSON to plain text format.

## Fast Deploy
This app can be deployed as a streaming SAS app in two lines of code:

```
filename mc url "https://raw.githubusercontent.com/sasjs/viya-log-parser/master/runme.sas";
%inc mc;
```

You can now open it at `YOURSERVER/SASJobExecution?_program=/Public/app/fileuploader/clickme`.

**NOTE** - in general, it is not recommended to execute code directly from the internet! Instead you can opt to navigate to the link below and copy paste it (after careful review) into your SAS Studio V session and run it directly.

https://raw.githubusercontent.com/sasjs/viya-log-parser/master/runme.sas



## Building from Source

To deploy this app, first install the SASjs CLI - full instructions [here](https://cli.sasjs.io/installation/).

Next, run `sasjs add` to prepare your target ([instructions](https://cli.sasjs.io/add/)).

Then run  `sasjs cb` to prepare the deployment SAS script.

It's also possible to build without using the SAS Script by running `sasjs add` (to authenticate) and `sasjs deploy` to deploy directly to Viya usin the APIs.  For this you will need the `"deployServicePack":true` attribute in your target.


## Closing remarks

If you have any problems, please just raise an [issue](https://github.com/sasjs/viya-log-parser/issues/new)!

For more information on the SASjs framework, see https://sasjs.io
