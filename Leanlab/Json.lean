/-
A tiny JSON subset for the HTTP API.

Accepted request bodies are one object with a single string field `text`.
Strings may contain UTF-8 and the escapes `"`, `\`, `/`, `b` is rejected,
`n`, `r`, `t`, and `\uXXXX` for a scalar that is not a surrogate.
The encoder escapes controls as `\u00XX`. This is not a general JSON library.
-/

namespace Leanlab.Json

def escape (s : String) : String := Id.run do
  let mut out := ""
  for c in s.toList do
    if c == '"' then
      out := out ++ "\\\""
    else if c == '\\' then
      out := out ++ "\\\\"
    else if c == '\n' then
      out := out ++ "\\n"
    else if c == '\r' then
      out := out ++ "\\r"
    else if c == '\t' then
      out := out ++ "\\t"
    else if c.toNat < 0x20 then
      let n := c.toNat
      let hex := Nat.toDigits 16 n
      let padded := List.replicate (4 - hex.length) '0' ++ hex
      out := out ++ "\\u" ++ String.ofList padded
    else
      out := out.push c
  return out

def str (s : String) : String :=
  "\"" ++ escape s ++ "\""

private def hexVal (c : Char) : Option Nat :=
  if '0' ≤ c && c ≤ '9' then some (c.toNat - '0'.toNat)
  else if 'a' ≤ c && c ≤ 'f' then some (c.toNat - 'a'.toNat + 10)
  else if 'A' ≤ c && c ≤ 'F' then some (c.toNat - 'A'.toNat + 10)
  else none

private def skipWs : List Char → List Char
  | c :: cs => if c == ' ' || c == '\n' || c == '\r' || c == '\t' then skipWs cs else c :: cs
  | [] => []

private def parseHex4 : List Char → Except String (Char × List Char)
  | a :: b :: c :: d :: rest => do
      let some av := hexVal a | throw "bad unicode escape"
      let some bv := hexVal b | throw "bad unicode escape"
      let some cv := hexVal c | throw "bad unicode escape"
      let some dv := hexVal d | throw "bad unicode escape"
      let n := ((av * 16 + bv) * 16 + cv) * 16 + dv
      if 0xD800 ≤ n && n ≤ 0xDFFF then
        throw "surrogate escape rejected"
      if n ≥ 0x110000 then
        throw "unicode escape out of range"
      return (Char.ofNat n, rest)
  | _ => throw "short unicode escape"

private def parseString (cs : List Char) : Except String (String × List Char) :=
  match cs with
  | '"' :: rest => parseFuel (rest.length + 1) [] rest
  | _ => throw "expected string"
where
  parseFuel (fuel : Nat) (acc : List Char) (cs : List Char) : Except String (String × List Char) :=
    match fuel with
    | 0 => throw "unterminated string"
    | fuel + 1 =>
      match cs with
      | [] => throw "unterminated string"
      | '"' :: rest => return (String.ofList acc.reverse, rest)
      | '\\' :: esc :: rest => do
          let (ch, rest) ←
            match esc with
            | '"' => pure ('"', rest)
            | '\\' => pure ('\\', rest)
            | '/' => pure ('/', rest)
            | 'n' => pure ('\n', rest)
            | 'r' => pure ('\r', rest)
            | 't' => pure ('\t', rest)
            | 'u' => parseHex4 rest
            | _ => throw "bad escape"
          parseFuel fuel (ch :: acc) rest
      | c :: rest =>
          if c.toNat < 0x20 then
            throw "raw control in string"
          else
            parseFuel fuel (c :: acc) rest

/-- Parse `{"text": "..."}`. Whitespace is allowed. Nothing else is. -/
def parseTextField (s : String) : Except String String := do
  match skipWs s.toList with
  | '{' :: rest =>
      let rest := skipWs rest
      let (key, rest) ← parseString rest
      if key != "text" then
        throw "expected field text"
      match skipWs rest with
      | ':' :: rest =>
          let (val, rest) ← parseString (skipWs rest)
          match skipWs rest with
          | '}' :: rest =>
              if (skipWs rest).isEmpty then
                return val
              else
                throw "trailing junk"
          | _ => throw "expected }"
      | _ => throw "expected :"
  | _ => throw "expected object"

end Leanlab.Json
