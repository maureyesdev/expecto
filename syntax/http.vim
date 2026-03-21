" Syntax highlighting for .http and .rest files (expecto.nvim)
" Inspired by the VSCode REST Client file format.

if exists("b:current_syntax")
  finish
endif

let b:current_syntax = "http"

" ── Case insensitivity for keywords ──────────────────────────────────────────
syntax case ignore

" ── Request separator: ### (3+ # chars, optionally followed by a label) ──────
syntax match httpSeparator /^###.*$/ contains=httpSeparatorLabel
syntax match httpSeparatorLabel /###\s\+.*$/ contained

" ── Comments: lines starting with # (not @-annotations) or // ────────────────
syntax match httpComment /^#\s.*$/
syntax match httpComment /^#$/
syntax match httpComment /^\/\/\s.*$/
syntax match httpComment /^\/\/$/

" ── File variable definitions: @name = value ─────────────────────────────────
syntax match httpVarDef /^@[a-zA-Z_][a-zA-Z0-9_-]*\s*=.*$/ contains=httpVarDefName,httpVarDefEq,httpVarRef,httpSystemVar
syntax match httpVarDefName /^@[a-zA-Z_][a-zA-Z0-9_-]*/ contained
syntax match httpVarDefEq /=/ contained

" ── Request metadata annotations: # @name, # @no-redirect, etc. ─────────────
syntax match httpAnnotation /^#\s*@[a-zA-Z][a-zA-Z0-9_-]*\(.*\)\?$/ contains=httpAnnotationKey,httpAnnotationValue
syntax match httpAnnotationKey /@[a-zA-Z][a-zA-Z0-9_-]*/ contained
syntax match httpAnnotationValue /\s\+.*$/ contained

" Same for // @name style
syntax match httpAnnotation /^\/\/\s*@[a-zA-Z][a-zA-Z0-9_-]*\(.*\)\?$/ contains=httpAnnotationKey,httpAnnotationValue

" ── HTTP methods ─────────────────────────────────────────────────────────────
syntax keyword httpMethod GET POST PUT DELETE PATCH HEAD OPTIONS CONNECT TRACE
  \ contained nextgroup=httpUrl skipwhite

" ── HTTP version ─────────────────────────────────────────────────────────────
syntax match httpVersion /HTTP\/[0-9]\+\(\.[0-9]\+\)\?/ contained

" ── Request line ─────────────────────────────────────────────────────────────
" METHOD URL [HTTP/version]
syntax match httpRequestLine /^\(GET\|POST\|PUT\|DELETE\|PATCH\|HEAD\|OPTIONS\|CONNECT\|TRACE\)\s\+\S.*$/
  \ contains=httpMethod,httpUrl,httpVersion

" URL-only request line (defaults to GET)
syntax match httpRequestLine /^https\?:\/\/\S\+/
  \ contains=httpUrl

" ── URL ──────────────────────────────────────────────────────────────────────
syntax match httpUrl /https\?:\/\/[^ \t]*/
  \ contained contains=httpVarRef,httpSystemVar

" Multi-line query param continuation
syntax match httpQueryContinuation /^\s*[?&][^#\n]*$/
  \ contains=httpVarRef,httpSystemVar

" ── Response status line (shown in response buffer) ──────────────────────────
syntax match httpResponseStatus /^HTTP\/[0-9]\+\(\.[0-9]\+\)\?\s\+[0-9]\{3\}.*$/
  \ contains=httpVersion,httpStatusCode,httpStatusText
syntax match httpStatusCode /\s[1-5][0-9][0-9]\s/ contained
syntax match httpStatusText /\s\(OK\|Created\|Accepted\|No Content\|Bad Request\|Unauthorized\|Forbidden\|Not Found\|Internal Server Error\|.*\)$/ contained

" ── Header lines: Name: Value ─────────────────────────────────────────────────
syntax match httpHeader /^[a-zA-Z][a-zA-Z0-9_-]*:\s.*$/
  \ contains=httpHeaderName,httpHeaderColon,httpHeaderValue
syntax match httpHeaderName /^[a-zA-Z][a-zA-Z0-9_-]*/ contained
syntax match httpHeaderColon /:/ contained
syntax match httpHeaderValue /\s.*$/ contained
  \ contains=httpVarRef,httpSystemVar,httpAuthScheme

" ── Auth scheme highlights inside header values ──────────────────────────────
syntax keyword httpAuthScheme Basic Bearer Digest AWS COGNITO contained

" ── Variable references: {{varName}} and {{%varName}} ────────────────────────
syntax match httpVarRef /{{[^$%{][^}]*}}/
  \ contains=httpVarRefBrace,httpVarRefName
syntax match httpVarRefBrace /{{/ contained
syntax match httpVarRefBrace /}}/ contained
syntax match httpVarRefName /[^$%{][^}]*/ contained

" Percent-encoded variable: {{%varName}}
syntax match httpVarRefEncoded /{{\%[a-zA-Z_][a-zA-Z0-9_-]*}}/

" ── System variable references: {{$varName [args]}} ─────────────────────────
syntax match httpSystemVar /{{$[a-zA-Z][a-zA-Z0-9]*\([^}]*\)\?}}/
  \ contains=httpSystemVarBrace,httpSystemVarName,httpSystemVarArgs
syntax match httpSystemVarBrace /{{/ contained
syntax match httpSystemVarBrace /}}/ contained
syntax match httpSystemVarName /\$[a-zA-Z][a-zA-Z0-9]*/ contained
syntax match httpSystemVarArgs /\s[^}]*/ contained

" ── Body file references: < ./file and <@ ./file ─────────────────────────────
syntax match httpBodyFile /^<@\?\([a-zA-Z0-9_-]\+\s\+\)\?\S.*$/ contains=httpBodyFileOp,httpBodyFilePath
syntax match httpBodyFileOp /^<@\?[a-zA-Z0-9_-]*/ contained
syntax match httpBodyFilePath /\S\+\s*$/ contained

" ── cURL command lines ───────────────────────────────────────────────────────
syntax match httpCurlCommand /^curl\s.*/
  \ contains=httpCurlKeyword,httpCurlFlag,httpUrl
syntax keyword httpCurlKeyword curl contained
syntax match httpCurlFlag /\s-\{1,2\}[a-zA-Z][a-zA-Z0-9_-]*/ contained

" ── GraphQL section label (informational, not formal syntax) ─────────────────
syntax match httpGraphQL /\cX-REQUEST-TYPE:\s*GraphQL/ contained

" ── Highlight links ──────────────────────────────────────────────────────────
highlight default link httpSeparator      Special
highlight default link httpSeparatorLabel Comment
highlight default link httpComment        Comment
highlight default link httpAnnotation     PreProc
highlight default link httpAnnotationKey  Keyword
highlight default link httpAnnotationValue String

highlight default link httpVarDef         Define
highlight default link httpVarDefName     Identifier
highlight default link httpVarDefEq       Operator

highlight default link httpMethod         Statement
highlight default link httpVersion        Type
highlight default link httpUrl            Underlined
highlight default link httpQueryContinuation Underlined

highlight default link httpResponseStatus  Title
highlight default link httpStatusCode      Number
highlight default link httpStatusText      String

highlight default link httpHeaderName      Identifier
highlight default link httpHeaderColon     Operator
highlight default link httpHeaderValue     String
highlight default link httpAuthScheme      Keyword

highlight default link httpVarRef          Special
highlight default link httpVarRefBrace     Delimiter
highlight default link httpVarRefName      Identifier
highlight default link httpVarRefEncoded   Special

highlight default link httpSystemVar       SpecialChar
highlight default link httpSystemVarBrace  Delimiter
highlight default link httpSystemVarName   Function
highlight default link httpSystemVarArgs   Number

highlight default link httpBodyFileOp      Operator
highlight default link httpBodyFilePath    String

highlight default link httpCurlKeyword     Statement
highlight default link httpCurlFlag        Identifier

highlight default link httpGraphQL         Type
