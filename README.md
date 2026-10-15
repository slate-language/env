# env — the process configuration, checked against a declared shape

**The configuration is read once, converted, and checked against a type the program declares — and
a program with a bad one is told every problem at once, before it starts.** The type is the whole
description: its keys are the variable names and its members say what each one is.

```
slate add github.com/slate-language/env
```

```slate
import { env } from env
import { stderr, exit } from slate:process

type Config = { PORT: integer, DATABASE_URL: string, DEBUG?: boolean }

val config = env(Config, { defaults: { PORT: "8080" }, file: ".env" }) match
    { ok: true, value } -> value
    { error } ->
        stderr(error + "\n")
        exit(1)

print(config.PORT + 1)
```

With `DEBUG=perhaps` set and `DATABASE_URL` not, it writes this and exits 1:

```
DATABASE_URL is not set, and has to be string
DEBUG is set, but not to boolean
```

**It is one file of ordinary slate.** It reads the environment through `slate:process` and a dotenv
file through `slate:fs`; a host with neither passes `source` and leaves out `file`.

## What there is

| | |
|---|---|
| `env(Shape, options = {})` | the variables `Shape` names, converted and checked — `{ ok: true, value }` or `{ ok: false, error }` |
| `dotenv(text, label = ".env")` | the variables a dotenv file's text sets, as an object of strings — `{ ok, value }` or `{ ok, error }` |

The options:

| | |
|---|---|
| `defaults` | an object of strings, used where nothing else sets a variable |
| `source` | an object of strings that **replaces** the process environment — what a test passes, and a host with none |
| `file` | a dotenv file to read first; **the environment wins over it**, and it wins over `defaults` |

`value` holds the members that are set, each converted to what the shape declared. A variable the
shape does not have is left out of it, so the rest of the environment never travels with the
configuration.

## The decisions

**The shape is the one validator, and nothing describes it a second time.** A shape cannot be read
back — slate deliberately has no reflection on a type — so this package never asks what a member
*is*. It asks the shape what it will *accept*: every variable starts as its text, and a member the
shape refuses a string for is offered an integer, then a number, then a boolean, keeping the first
the shape accepts. A last `mismatch` decides. So a range or a union of literals is checked exactly as
the program declared it:

```slate
type Config = { PORT: 1..65535, MODE: "dev" | "prod" }
```

**Every reading is strict.** `number` is generous on purpose — it reads `" 8"`, `"0x10"` and `"1e3"`
— and a configuration should not be. An integer is digits with an optional sign; a number may have a
fraction and an exponent, and is a real unless it is whole digits; a boolean is `true`, `false`, `1`
or `0` and nothing else. `"8x"` is a problem, not 8.

**A bad configuration is an answer, not a fault.** The text came from outside the program, which is
the line slate draws between its [two failure channels](https://slatelang.dev/reference/faults/): a
result for what the caller was always going to deal with, a fault for a defect in the program. So
`env` answers `{ ok: false, error }`, and the program decides what refusing to start looks like.
**The options are the program's own**, so a mistake in them — an option that does not exist, a
default that is not a string, a default for a variable the shape does not have — is a fault.

**No value is ever in a message.** A variable may be a password or a key, and an error message goes
to a terminal, a log and a CI page. A line names the variable and what was wanted; a bad line of a
dotenv file is named by its number and never quoted.

**Every problem is reported at once**, a line each: a missing variable, one that will not convert,
one the shape refuses, and every line of the file that could not be read. Fixing a deployment one
restart at a time is the thing this exists to prevent.

**A file that is not there is no file.** A development machine has a `.env`; a deployment usually
has its environment and nothing else, and the same program runs on both.

## The dotenv file

The usual format:

```
# a comment, and a blank line, are passed over

PORT=3000
export DEBUG=1
DATABASE_URL=postgres://localhost/app   # a comment after a value
GREETING="hello\nworld"
LITERAL='kept exactly, \n and all'
KEY="-----BEGIN KEY-----
a quoted value may run over several lines
-----END KEY-----"
```

- a `#` begins a comment at the start of a line, or after a space or tab in a bare value — `a#b` is a
  value;
- double quotes take the escapes `\n`, `\r`, `\t`, `\"` and `\\`; single quotes take nothing;
- a name set twice keeps the later value.

## With `sluice`

```slate
import { api } from sluice
import { serve } from slate:http
import { env } from env
import { stderr, exit } from slate:process

type Config = { PORT: integer, DATABASE_URL: string }

val config = env(Config, { file: ".env" }) match
    { ok: true, value } -> value
    { error } ->
        stderr(error + "\n")
        exit(1)

val app = api()

serve(config.PORT, app)
```

## Running the suite

```
slate test tests
slate test --js tests
```

Both are green. **It needs slate 0.1.22 or later**, the first with `environment()` in
`slate:process`: an optional member can only be found in an environment that can be listed, since
the shape cannot say which members it has.
