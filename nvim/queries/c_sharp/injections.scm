; extends

; Add sql language injection to strings marked with a comment containing language=<language>, e.g. language=sql
; https://www.jetbrains.com/help/rider/Language_Injections.html#use-comments
(
 (comment) @injection.language (#gsub! @injection.language ".*language=(.*)" "%1")
 . ; Only match sibling between comment and a string
 [
  ; string as a global declaration
  ; var query = "select * from table";
  ; string query = "select * from table";
  (global_statement
    (local_declaration_statement
      (variable_declaration
        type: (implicit_type)?
        type: (predefined_type)?
        (variable_declarator
          name: (identifier)?
          (string_literal
            (string_literal_content) @injection.content)))))

  ; string inside method/function
  ; var query = "select * from table";
  ; string query = "select * from table";
  (local_declaration_statement
    (variable_declaration
      type: (implicit_type)?
      type: (predefined_type)?
      (variable_declarator
        name: (identifier)?
        (string_literal
          (string_literal_content) @injection.content))))

  ; raw string literal inside method/function
  ; var query = """select * from table""";
  ; string query = """select * from table""";
  (local_declaration_statement
    (variable_declaration
      type: (implicit_type)?
      type: (predefined_type)?
      (variable_declarator
        name: (identifier)?
        (raw_string_literal
          (raw_string_start)?
          (raw_string_content) @injection.content
          (raw_string_end)?))))

  ; string field
  ; private readonly string query = "select * from table";
  (field_declaration
    (variable_declaration
      (variable_declarator
        (string_literal
          (string_literal_content) @injection.content))))
  ]
 (#set! injection.include-children)
 )

(
 (comment) @injection.language (#gsub! @injection.language ".*language=(.*)" "%1")
 . ; Only match sibling between comment and a string
 ; verbatim string literal inside method/function
 ; var query = @"select * from table";
 ; string query = @"select * from table";
 (local_declaration_statement
   (variable_declaration
     type: (implicit_type)?
     type: (predefined_type)?
     (variable_declarator
       name: (identifier)?
       (verbatim_string_literal) @injection.content (#offset! @injection.content 0 2 0 -1))))
 )

; Interpolated strings need to be combined after captured
; that's why we separate them into another rule here
; var query = $"select * from table";
; string query = $"select * from table";
(
 (comment) @injection.language (#gsub! @injection.language ".*language=(.*)" "%1")
 . ; Only match sibling between comment and a string
 (local_declaration_statement
   (variable_declaration
     (variable_declarator
       (interpolated_string_expression
         [
          (string_content)
          ] @injection.content
         ))))
 (#set! injection.combined)
 )
