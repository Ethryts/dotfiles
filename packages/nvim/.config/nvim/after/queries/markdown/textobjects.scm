;extends

(fenced_code_block (code_fence_content) @class.inner) @class.outer

(paragraph) @function.outer @function.inner

(raise_statement
  (expression_list 
    (identifier) @error
    (_) @msg
  ) 
)
