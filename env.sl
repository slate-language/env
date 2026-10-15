// env -- the process configuration, read once, converted, and checked against a declared shape.
//
//     import { env } from env
//
//     type Config = { PORT: integer, DATABASE_URL: string, DEBUG?: boolean }
//
//     env(Config, { defaults: { PORT: "8080" }, file: ".env" }) match
//         { ok: true, value } -> serve(value.PORT, app)
//         { error } -> ...
//
// **The shape is the one validator.** Its keys are the variable names, and what each member is
// converted to is decided by asking the shape, never by a second description of it: every variable
// starts as the text it is, and a member the shape refuses a string for is offered an integer, then
// a number, then a boolean, each read strictly, keeping the first the shape accepts. A last
// `mismatch` is what decides whether the configuration is good.
//
// **A bad configuration is an ANSWER and not a fault**, because the text came from outside the
// program -- slate's two-channel rule. Every problem is in the one answer, a line each, and no line
// ever carries a variable's value: a value may be a secret, so a line names the variable and what
// was wanted.

import { environment } from slate:process
import { existsSync, readFileSync } from slate:fs
import { regex } from slate:regex

// -- strict readings of a variable's text -----------------------------------------------------------

// A whole number: digits with an optional sign, and nothing else. `number` alone is generous --
// it reads `" 8"`, `"0x10"` and `"1e3"` -- which is right for a person typing and wrong for a
// configuration, where `"8x"` is a mistake and not an 8.
val Whole = regex("^[+-]?[0-9]+$")

// A decimal number, with an optional fraction and exponent.
val Decimal = regex("^[+-]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][+-]?[0-9]+)?$")

// What a name in a `.env` file may be: a shell variable name.
val Name = regex("^[A-Za-z_][A-Za-z0-9_]*$")

// The readings of `text` worth offering a member the shape refused the text itself for, in the order
// they are offered. A reading that does not parse is not offered at all.
//
// **The number reading is always a real**, so a member declared `integer` is satisfied only by the
// whole-number reading: `"1e3"` is not an integer setting, though `number` reads it as 1000.
readings(text: string) -> array
    var out = []
    if Whole.test(text)
        val n = number(text)
        if n is integer then push(out, n)
    if Decimal.test(text) then push(out, real(number(text)))
    if text == "true" || text == "1" then push(out, true)
    if text == "false" || text == "0" then push(out, false)
    out

// -- the dotenv format ------------------------------------------------------------------------------

// The text of a double-quoted value, from just after its opening quote. Answers the value, how many
// characters were taken including the closing quote, and whether one was found.
//
// The escapes are the ones every dotenv reader takes: `\n`, `\r`, `\t`, `\"` and `\\`. Any other
// backslash is kept as it was written.
double_quoted(s: string)
    var out = ""
    var i = 0
    while i < s.length
        val c = s[i]
        if c == "\""
            return { text: out, used: i + 1, closed: true }
        if c == "\\" && i + 1 < s.length
            val e = s[i + 1]
            if e == "n" then out += "\n"
            elif e == "r" then out += "\r"
            elif e == "t" then out += "\t"
            elif e == "\"" || e == "\\" then out += e
            else out += c + e
            i += 2
        else
            out += c
            i += 1
    { text: out, used: i, closed: false }

// The text of a single-quoted value: everything up to the next `'`, exactly as written.
single_quoted(s: string)
    val at = s.indexOf("'")
    if at == null then return { text: s, used: s.length, closed: false }
    { text: s[0..<at], used: at + 1, closed: true }

// An unquoted value ends at a `#` that follows a space or a tab, which begins a comment. A `#` inside
// a word is part of it, so `a#b` is a value and `a #b` is `a`.
unquoted(s: string) -> string
    var i = 0
    while i < s.length
        if s[i] == "#" && (i == 0 || s[i - 1] == " " || s[i - 1] == "\t")
            return s[0..<i].trimEnd()
        i += 1
    s.trimEnd()

// `dotenv(text, label)` -- the variables a `.env` file sets, as an object of strings.
//
// Answers `{ ok: true, value }` or `{ ok: false, error }`, a line of `error` per line of the file
// that could not be read -- each named by its number and never quoted, a line of a `.env` file being
// as likely as not to hold a secret. `label` is what the lines are said to be in.
//
// The format is the usual one: blank lines and lines beginning `#` are passed over, `export` in
// front of a name is allowed, a value may be double-quoted (with escapes, and over several lines),
// single-quoted (taken exactly) or bare (ending at a ` #` comment), and a name set twice keeps the
// later value.
export dotenv(text: string, label: string = ".env")
    val lines = text.split("\n")
    val value = {}
    var problems = []
    var i = 0
    while i < lines.length
        val number_of_line = i + 1
        var line = lines[i].trim()
        i += 1
        if line == "" || line.startsWith("#") then continue
        if line.startsWith("export ") || line.startsWith("export\t")
            line = line[7..<line.length].trimStart()
        val eq = line.indexOf("=")
        if eq == null
            push(problems, label + " line " + string(number_of_line) + " is not NAME=value")
            continue
        val name = line[0..<eq].trim()
        if !Name.test(name)
            push(problems, label + " line " + string(number_of_line) + " does not begin with a variable name")
            continue
        var rest = line[eq + 1..<line.length].trimStart()
        if rest.startsWith("\"") || rest.startsWith("'")
            val quote = rest[0]
            var body = rest[1..<rest.length]
            var got = if quote == "\"" then double_quoted(body) else single_quoted(body)
            // A quoted value may run on over the lines after it, which is how a key file is written
            // into one. The raw lines are joined back, since the trim above belongs to the first.
            while !got.closed && i < lines.length
                body = body + "\n" + lines[i].trimEnd()
                i += 1
                got = if quote == "\"" then double_quoted(body) else single_quoted(body)
            if !got.closed
                push(problems, label + " line " + string(number_of_line) + " opens a quote that never closes")
                continue
            val after = body[got.used..<body.length].trim()
            if after != "" && !after.startsWith("#")
                push(problems, label + " line " + string(number_of_line) + " has more after its closing quote")
                continue
            value[name] = got.text
        else
            value[name] = unquoted(rest)
    if problems.length > 0 then return { ok: false, error: problems.join("\n") }
    { ok: true, value }

// -- the options ------------------------------------------------------------------------------------

val Options = ["defaults", "source", "file"]

// An options object is the program's own, so a mistake in one is a defect in the program and FAULTS.
// Only what came from outside -- the environment and the file -- is answered.
strings(o, what: string)
    if !(o is object) then throw "env: `" + what + "` has to be an object of strings"
    for k in keys(o)
        if !(o[k] is string)
            throw "env: `" + what + "` has to be an object of strings, and its `" + k + "` is not a string"

checked(options)
    if !(options is object) then throw "env: the options have to be an object"
    for k in keys(options)
        if !Options.includes(k)
            throw "env: `" + k + "` is not an option; the options are defaults, source and file"
    if has(options, "defaults") then strings(options.defaults, "defaults")
    if has(options, "source") then strings(options.source, "source")
    if has(options, "file") && !(options.file is string)
        throw "env: `file` has to be the path of a dotenv file"

// -- reading ----------------------------------------------------------------------------------------

// The names the shape has, out of `names`. **Asked of the shape, since a shape cannot be read
// back**: each name is given a value no variable can hold -- an empty object -- and the shape's own
// `mismatch` says which of them it refused. A name it said nothing about is one it does not have.
members(Shape, names: array)
    val probe = {}
    for k in names
        probe[k] = {}
    val out = {}
    for m in Shape.mismatch(probe)
        out[m.path.split(".")[0]] = true
    out

// Whether the shape has a complaint about `name` in `value`.
refused(Shape, value, name: string) -> boolean
    Shape.mismatch(value).some((m) -> m.path == name || m.path.startsWith(name + "."))

// One line for one complaint the shape has. **The value is never in it**: it names the variable and
// what was wanted, and nothing that was set.
complaint(m) -> string
    if m.got == "nothing" then m.path + " is not set, and has to be " + m.wanted
    else m.path + " is set, but not to " + m.wanted

// `env(Shape, options)` -- the variables `Shape` names, converted and checked.
//
// Answers `{ ok: true, value }`, where `value` holds the members that are set, each converted to what
// the shape declared -- or `{ ok: false, error }`, every problem a line of it.
//
// The options:
//
// - `defaults` -- an object of strings, used where nothing else sets a variable. A shape cannot
//   carry a default, so this is where one is written.
// - `source` -- an object of strings that stands in for the process environment. A test passes one,
//   and so does a host with no environment of its own.
// - `file` -- a dotenv file read before the environment. **The environment wins over the file**,
//   and a file that is not there is no file -- a deployment usually has none.
//
// A variable the shape does not have is ignored, and a default naming one is a FAULT: it can only
// be a misspelling, and a default nobody reads is a setting that silently never applies.
export env(Shape, options = {})
    if !(Shape is shape) then throw "env: the first argument has to be a shape -- a declared type"
    checked(options)
    val defaults = options.defaults ?? {}
    var problems = []

    val set = {}
    for k in keys(defaults)
        set[k] = defaults[k]

    val file = options.file ?? null
    if file != null && existsSync(file)
        val read = readFileSync(file)
        if !read.ok
            push(problems, read.error)
        else
            val parsed = dotenv(read.value, file)
            if parsed.ok
                for k in keys(parsed.value)
                    set[k] = parsed.value[k]
            else
                push(problems, parsed.error)

    val outside = options.source ?? environment()
    for k in keys(outside)
        set[k] = outside[k]

    val known = members(Shape, keys(set))
    for k in keys(defaults)
        if !has(known, k)
            throw "env: there is a default for `" + k + "`, which the shape does not have"

    val value = {}
    for k in keys(set)
        if has(known, k) then value[k] = set[k]

    // Every member the shape refused its text for is offered the other readings of that text.
    for m in Shape.mismatch(value)
        if m.got == "string" && has(value, m.path)
            val text = value[m.path]
            var taken = false
            for reading in readings(text)
                if !taken
                    value[m.path] = reading
                    taken = !refused(Shape, value, m.path)
            if !taken then value[m.path] = text

    for m in Shape.mismatch(value)
        push(problems, complaint(m))

    if problems.length > 0 then return { ok: false, error: problems.join("\n") }
    { ok: true, value }
