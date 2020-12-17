const parseLogLines = () => {
  let logText = document.querySelector('#log_text').value
  let logJson = JSON.parse(logText)

  let logLines = ''

  for (let item of logJson.items) {
    logLines += `${item.line}\n`
  }

  let logResult = document.querySelector('#log_result').innerHTML = logLines
}