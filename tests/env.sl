// The whole package, from the outside, under both hosts.
//
// **Every test but two passes a `source`**, which stands in for the process environment, so what a
// test reads is what it wrote. The two that do not are the ones that prove the real environment is
// read at all, and they ask only for `PATH`, which every host running this suite has.

import { env, dotenv } from "../env.sl"
import { writeFileSync, removeSync } from slate:fs

type Config = { PORT: integer, DATABASE_URL: string, DEBUG?: boolean }
type Texts = { NAME: string, FLAG: string }
type Flags = { A: boolean, B: boolean, C: boolean, D: boolean }
type Wholes = { A: integer, B: integer, C: integer, D: integer, E: integer, F: integer, G: integer }
type Numbers = { A: number, B: number, C: number, D: number }
type Bounded = { PORT: 1..65535, MODE: "dev" | "prod" }
type Secret = { PORT: integer, TOKEN: integer, FLAG: boolean }
type Path = { PATH: string }
type MaybePath = { PATH?: string, NO_SUCH_VARIABLE_FOR_ENV_TESTS?: string }

// The dotenv file the file tests write, beside wherever the suite is run from.
val File = "env-test.env"

// The value, where `r` is the good answer -- and a failure naming the error where it is not.
good(r)
    assert(r.ok, "wanted a configuration, got: " + (r.error ?? ""))
    r.value

// The lines of the error, where `r` is the bad answer.
bad(r) -> array
    assert(!r.ok, "wanted problems, got a configuration")
    r.error.split("\n")

withFile(text: string, fn: function)
    writeFileSync(File, text)
    try
        fn()
    catch e
        removeSync(File)
        throw e
    removeSync(File)

// -- conversion -------------------------------------------------------------------------------------

@test
EACH_MEMBER_IS_CONVERTED_TO_WHAT_THE_SHAPE_DECLARED()
    val c = good(env(Config, { source: { PORT: "8080", DATABASE_URL: "postgres://x", DEBUG: "true" } }))
    assertEq(c, { PORT: 8080, DATABASE_URL: "postgres://x", DEBUG: true })
    assert(c.PORT is integer)

@test
A_STRING_STAYS_AS_IT_IS_EVEN_WHERE_IT_LOOKS_LIKE_A_NUMBER()
    assertEq(good(env(Texts, { source: { NAME: "42", FLAG: "true" } })), { NAME: "42", FLAG: "true" })

@test
A_BOOLEAN_TAKES_TRUE_FALSE_ONE_AND_ZERO()
    val c = good(env(Flags, { source: { A: "true", B: "false", C: "1", D: "0" } }))
    assertEq(c, { A: true, B: false, C: true, D: false })

@test
A_BOOLEAN_REFUSES_ANYTHING_ELSE()
    val lines = bad(env(Flags, { source: { A: "yes", B: "TRUE", C: "2", D: "" } }))
    assertEq(lines.length, 4)
    for line in lines
        assert(line.endsWith("is set, but not to boolean"), line)

@test
AN_INTEGER_IS_READ_STRICTLY()
    val c = good(env(Wholes, { source: { A: "0", B: "-12", C: "+7", D: "9007199254740993", E: "0", F: "1", G: "99999999999999999999" } }))
    // A slate integer has no upper bound, so neither has a setting; a range in the shape is the bound.
    assertEq(c, { A: 0, B: -12, C: 7, D: 9007199254740993, E: 0, F: 1, G: 99999999999999999999 })

@test
AN_INTEGER_REFUSES_WHAT_number_WOULD_HAVE_BEEN_GENEROUS_ABOUT()
    // `number` reads every one of these but the first; a configuration is not a person typing.
    val r = env(Wholes, { source: { A: "8x", B: " 8", C: "1e3", D: "0x10", E: "1.5", F: "", G: "1_000" } })
    val lines = bad(r)
    assertEq(lines, ["A is set, but not to integer", "B is set, but not to integer", "C is set, but not to integer", "D is set, but not to integer", "E is set, but not to integer", "F is set, but not to integer", "G is set, but not to integer"])

@test
A_NUMBER_TAKES_A_WHOLE_NUMBER_AS_ONE_AND_ANYTHING_ELSE_AS_A_REAL()
    val c = good(env(Numbers, { source: { A: "8080", B: "1.5", C: "1e3", D: "-.25" } }))
    assertEq(c, { A: 8080, B: 1.5, C: 1000.0, D: -0.25 })
    assert(c.A is integer)
    assert(c.C is real)

@test
A_NUMBER_REFUSES_TEXT()
    assertEq(bad(env(Numbers, { source: { A: "abc", B: "1.2.3", C: "1", D: "-" } })), ["A is set, but not to number", "B is set, but not to number", "D is set, but not to number"])

@test
THE_SHAPE_STAYS_THE_VALIDATOR_AFTER_CONVERSION()
    // A range and a union of literals are checked by the shape, not by this package.
    assertEq(good(env(Bounded, { source: { PORT: "443", MODE: "prod" } })), { PORT: 443, MODE: "prod" })
    val lines = bad(env(Bounded, { source: { PORT: "70000", MODE: "staging" } }))
    assertEq(lines.length, 2)
    assert(lines[0].startsWith("PORT is set, but not to "), lines[0])
    assert(lines[1].startsWith("MODE is set, but not to "), lines[1])

@test
A_VARIABLE_THE_SHAPE_DOES_NOT_HAVE_IS_LEFT_OUT()
    val c = good(env(Config, { source: { PORT: "1", DATABASE_URL: "x", HOME: "/home/me", OTHER: "8" } }))
    assertEq(c, { PORT: 1, DATABASE_URL: "x" })

// -- optional members -------------------------------------------------------------------------------

@test
AN_OPTIONAL_MEMBER_THAT_IS_NOT_SET_IS_ABSENT()
    val c = good(env(Config, { source: { PORT: "1", DATABASE_URL: "x" } }))
    assert(!has(c, "DEBUG"))

@test
AN_OPTIONAL_MEMBER_THAT_IS_SET_IS_CONVERTED_AND_CHECKED()
    assertEq(good(env(Config, { source: { PORT: "1", DATABASE_URL: "x", DEBUG: "0" } })).DEBUG, false)
    assertEq(bad(env(Config, { source: { PORT: "1", DATABASE_URL: "x", DEBUG: "maybe" } })), ["DEBUG is set, but not to boolean"])

// -- defaults ---------------------------------------------------------------------------------------

@test
A_DEFAULT_IS_USED_WHERE_NOTHING_SETS_THE_VARIABLE()
    val c = good(env(Config, { defaults: { PORT: "8080" }, source: { DATABASE_URL: "x" } }))
    assertEq(c.PORT, 8080)

@test
A_DEFAULT_GIVES_WAY_TO_THE_ENVIRONMENT()
    val c = good(env(Config, { defaults: { PORT: "8080" }, source: { PORT: "9090", DATABASE_URL: "x" } }))
    assertEq(c.PORT, 9090)

@test
A_DEFAULT_IS_CHECKED_LIKE_ANYTHING_ELSE()
    assertEq(bad(env(Config, { defaults: { PORT: "eighty" }, source: { DATABASE_URL: "x" } })), ["PORT is set, but not to integer"])

@test
A_DEFAULT_FOR_A_NAME_THE_SHAPE_DOES_NOT_HAVE_IS_A_FAULT()
    // It can only be a misspelling, and it would never apply.
    assertFaults(() -> env(Config, { defaults: { PROT: "8080" }, source: { PORT: "1", DATABASE_URL: "x" } }), "default for `PROT`")

@test
A_DEFAULT_FOR_AN_OPTIONAL_MEMBER_IS_ALLOWED()
    assertEq(good(env(Config, { defaults: { DEBUG: "false" }, source: { PORT: "1", DATABASE_URL: "x" } })).DEBUG, false)

// -- failure ----------------------------------------------------------------------------------------

@test
EVERY_PROBLEM_IS_REPORTED_AT_ONCE_AND_EACH_NAMES_ITS_VARIABLE()
    val lines = bad(env(Config, { source: { PORT: "80a", DEBUG: "perhaps" } }))
    assertEq(lines.length, 3)
    assert(lines.some((l) -> l == "PORT is set, but not to integer"))
    assert(lines.some((l) -> l == "DATABASE_URL is not set, and has to be string"))
    assert(lines.some((l) -> l == "DEBUG is set, but not to boolean"))

@test
NO_VALUE_IS_EVER_IN_A_MESSAGE()
    val r = env(Secret, { source: { PORT: "hunter2-port", TOKEN: "s3cr3t-token", FLAG: "pa55word" } })
    assert(!r.ok)
    assert(!r.error.contains("hunter2"))
    assert(!r.error.contains("s3cr3t"))
    assert(!r.error.contains("pa55word"))
    assertEq(bad(r).length, 3)

@test
NO_VALUE_FROM_A_FILE_IS_EVER_IN_A_MESSAGE_EITHER()
    withFile("TOKEN=s3cr3t-token\nthis line is pa55word\nKEY=\"hunter2\n", () ->
        val r = env(Config, { file: File, source: { PORT: "1", DATABASE_URL: "x" } })
        assert(!r.ok)
        assert(!r.error.contains("s3cr3t"))
        assert(!r.error.contains("pa55word"))
        assert(!r.error.contains("hunter2"))
        assertEq(bad(r), ["env-test.env line 2 is not NAME=value", "env-test.env line 3 opens a quote that never closes"]))

// -- the file ---------------------------------------------------------------------------------------

@test
THE_FILE_IS_READ_AND_CONVERTED_LIKE_THE_ENVIRONMENT()
    withFile("PORT=3000\nDATABASE_URL=postgres://db/app\nDEBUG=1\n", () ->
        assertEq(good(env(Config, { file: File, source: {} })), { PORT: 3000, DATABASE_URL: "postgres://db/app", DEBUG: true }))

@test
THE_ENVIRONMENT_WINS_OVER_THE_FILE_AND_THE_FILE_OVER_A_DEFAULT()
    withFile("PORT=3000\nDATABASE_URL=from-file\n", () ->
        val c = good(env(Config, { file: File, defaults: { PORT: "1", DEBUG: "true" }, source: { DATABASE_URL: "from-environment" } }))
        assertEq(c, { PORT: 3000, DATABASE_URL: "from-environment", DEBUG: true }))

@test
A_FILE_THAT_IS_NOT_THERE_IS_NO_FILE()
    // A deployment usually has no `.env`; its environment is the configuration.
    assertEq(good(env(Config, { file: "no-such-file.env", source: { PORT: "1", DATABASE_URL: "x" } })).PORT, 1)

@test
COMMENTS_AND_BLANK_LINES_ARE_PASSED_OVER()
    val r = good(dotenv("# a comment\n\n   # an indented one\nA=1\n\nB=2 # after a value\nC=a#b\nD=# all comment\n"))
    assertEq(r, { A: "1", B: "2", C: "a#b", D: "" })

@test
DOUBLE_QUOTES_TAKE_ESCAPES_AND_KEEP_A_HASH()
    val r = good(dotenv("A=\"two\\nlines\"\nB=\"a # not a comment\"\nC=\"say \\\"hi\\\"\" # a comment\nD=\"back\\\\slash\"\nE=\"\"\n"))
    assertEq(r, { A: "two\nlines", B: "a # not a comment", C: "say \"hi\"", D: "back\\slash", E: "" })

@test
SINGLE_QUOTES_TAKE_THE_TEXT_EXACTLY()
    val r = good(dotenv("A='no \\n escape'\nB='a # b'\nC='say \"hi\"'\n"))
    assertEq(r, { A: "no \\n escape", B: "a # b", C: "say \"hi\"" })

@test
A_QUOTED_VALUE_MAY_RUN_OVER_SEVERAL_LINES()
    val r = good(dotenv("KEY=\"-----BEGIN-----\nabc\n-----END-----\"\nNEXT=1\n"))
    assertEq(r, { KEY: "-----BEGIN-----\nabc\n-----END-----", NEXT: "1" })

@test
EXPORT_IN_FRONT_SPACES_AROUND_AND_WINDOWS_LINE_ENDINGS_ARE_ALLOWED()
    val r = good(dotenv("export A=1\r\n  B  =  two words  \r\nC=\r\n"))
    assertEq(r, { A: "1", B: "two words", C: "" })

@test
A_NAME_SET_TWICE_KEEPS_THE_LATER_VALUE()
    assertEq(good(dotenv("A=1\nA=2\n")), { A: "2" })

@test
EVERY_BAD_LINE_IS_NAMED_BY_ITS_NUMBER()
    val r = dotenv("A=1\nnot a setting\n9X=2\nB=\"open\nC='x' trailing\n", "app.env")
    assertEq(bad(r), ["app.env line 2 is not NAME=value", "app.env line 3 does not begin with a variable name", "app.env line 4 opens a quote that never closes"])

@test
TEXT_AFTER_A_CLOSING_QUOTE_IS_A_PROBLEM()
    assertEq(bad(dotenv("A=\"x\" y\nB='x' # fine\n")), [".env line 1 has more after its closing quote"])

// -- the real environment ---------------------------------------------------------------------------

@test
WITHOUT_A_SOURCE_THE_PROCESS_ENVIRONMENT_IS_READ()
    assert(good(env(Path)).PATH is string)

@test
AN_OPTIONAL_MEMBER_IS_FOUND_IN_THE_PROCESS_ENVIRONMENT()
    // The reason `environment()` was needed: a shape cannot list its optional members.
    val c = good(env(MaybePath))
    assert(c.PATH is string)
    assert(!has(c, "NO_SUCH_VARIABLE_FOR_ENV_TESTS"))

// -- the program's own mistakes fault --------------------------------------------------------------

@test
A_FIRST_ARGUMENT_THAT_IS_NOT_A_SHAPE_IS_A_FAULT()
    assertFaults(() -> env({ PORT: "integer" }, { source: {} }), "has to be a shape")

@test
AN_OPTION_THAT_DOES_NOT_EXIST_IS_A_FAULT()
    assertFaults(() -> env(Config, { sources: {} }), "`sources` is not an option")

@test
A_SOURCE_OR_DEFAULT_THAT_IS_NOT_ALL_STRINGS_IS_A_FAULT()
    assertFaults(() -> env(Config, { source: { PORT: 8080 } }), "its `PORT` is not a string")
    assertFaults(() -> env(Config, { defaults: { PORT: 8080 } }), "its `PORT` is not a string")
    assertFaults(() -> env(Config, { file: 1 }), "`file` has to be")
