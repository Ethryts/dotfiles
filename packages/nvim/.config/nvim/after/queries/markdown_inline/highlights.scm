;extends

; Disable line conceal for fenced code blocks
; (override upstream queries that use #conceal_lines)

[
  (shortcut_link)
] @nospell

(strikethrough
(emphasis_delimiter) 
(strikethrough 
  (emphasis_delimiter) 
  (emphasis_delimiter)) 
(emphasis_delimiter))@markup.doublestrikethrough 
