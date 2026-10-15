{
    name: "env",
    version: "0.1.0",

    // One file, so one door. It needs slate 0.1.22, the first with `environment()` in
    // `slate:process` -- a shape cannot be read back, so the environment has to be listable for an
    // optional member to be found in it.
    main: "env.sl",
}
