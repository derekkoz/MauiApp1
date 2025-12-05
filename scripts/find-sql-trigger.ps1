# Recursively search source files for function attributes or ToDo/changefeed references.
$patterns = @(
  'sql_trigger_todo',
  '\[FunctionName\(',
  '\[Function\(',
  'CHANGETABLE',
  'CHANGETABLE\(CHANGES',
  'ToDo\b',
  '\bcompleted\b'
)

Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch '\\\\bin\\\\|\\\\obj\\\\' -and $_.Extension -in '.cs','.fs','.sql','.json','.csproj' } |
  ForEach-Object {
    $matches = Select-String -Path $_.FullName -Pattern $patterns -AllMatches -CaseSensitive:$false -ErrorAction SilentlyContinue
    if ($matches) {
      foreach ($m in $matches) {
        [PSCustomObject]@{
          File = $_.FullName
          LineNumber = $m.LineNumber
          Match    = $m.Matches.Value -join ', '
          Text     = $m.Line.Trim()
        }
      }
    }
  } | Sort-Object File, LineNumber | Format-Table -AutoSize