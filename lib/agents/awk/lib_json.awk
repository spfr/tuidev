# lib/agents/awk/lib_json.awk — JSON strings, shared by json.awk and
# report.awk:
#   js(s)   a JSON string: quotes and backslashes escaped, a tab as \t, other
#           control characters dropped;
#   opt(s)  the same, or null for "-" and "".

function js(s,   o, i, c, n) {
    n = length(s); o = ""
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "\\") o = o "\\\\"; else if (c == "\"") o = o "\\\""; else if (c == "\t") o = o "\\t"
        else if (c >= " ") o = o c
    }
    return "\"" o "\""
}
function opt(s) { return s == "-" || s == "" ? "null" : js(s) }
