# Roadmap for Packer v2

`packer` has become bloated, compilation (at least as it currently stands) has proven confusing and probably not necessary, and the codebase has become messy and hard to maintain.

As such, I'm proposing/working on (very slowly, as my OSS time is quite limited in my current job) an incremental rewrite of `packer`.
The below is a high-level overview of this plan.
Comments and additions are welcome and encouraged!

## General principles

`packer`'s code currently suffers from some poor software development practices largely stemming from getting "discovered" before it had time to become polished.
We want to avoid these pitfalls in the rewrite:

- Document all functions with emmylua-style comments: `packer` has very sparse documentation in its codebase. New/updated functions need to be appropriately documented.
- Add tests where possible: testing a package manager can be a pain because of requirements to interact with the file system, etc. However, `packer`'s current tests do not cover much, and new code should at least strongly consider adding unit tests.
- Avoid giant functions: `packer`'s logic contains some monstrous functions (e.g., `manage`, the main compilation logic, etc.) that are difficult to work with. New code should strive to use more, simpler functions in a more modular design.
- Prioritize clean, performant code over total flexibility: `packer`'s design allows for a very flexible range of input formats. Although we don't want to completely lose this property, supporting all of these formats (and other use cases) has contributed to code bloat. If there's a choice to be made between losing some flexibility and significantly increasing the complexity of the code, seriously consider removing the complexity.
- Reduce redundancy: `packer` currently has an annoying amount of redundant/overlapping functionality (the worst offenders are the `requires`/`wants`/`after` family of keywords, but there's also duplication of logic in the utilities, etc.). The rewrite should aim to reduce this.

## Stage 1: Remove compilation and clean up main interface. Breaking changes

We want the rewrite process to be as unintrusive as possible while still allowing for significant, potentially breaking changes.
As such, the first stage should contain all of the significant breaking changes to reduce the number of times users need to adapt.
The goals of the first stage are:

- [ ] Mostly remove compilation: this step involves moving to dynamic handlers for plugin specs and only "compiling" (really, caching) information that we can automatically recompile as needed, like additional filepaths to source, etc.
  - [x] Make main module lightweight: if `packer` is no longer relying on the compiled file being lightweight, its main module must become cheaper to `require`, as this will be necessary at all startups. This is mostly a question of reducing the amount that `packer` pulls in at the top level (e.g., moving things like management operations more fully into their own modules, reducing the reliance on utils modules, etc.).
  - [x] Implement fast runtime handler framework: To replace the compiled file, we will introduce a notion of "keyword handlers": simple functions which are responsible for implementing, at runtime, the behavior of a single previously-compiled keyword. See `lua/packer/handlers.lua` for the current spec and implementation of this idea.
  - [ ] Implement compiled keywords as handlers: Work in progress/current state of the rewrite. All the existing keywords from `packer/compile.lua` need to be ported to handlers. This involves dealing with `compile.lua`'s tricky logic in some places, and is a key point for simplification.
  - [ ] Implement `load` function to process and execute handlers: The final step of moving away from compilation is to write a function that runs the handlers on the plugin specs to generate lazy-loaders, run `setup` and `config` functions, etc. The trick here will be making this sufficiently fast.
  - [ ] Potentially implement path caching, etc.: Once the bulk of compilation is gone, we may wish to investigate adding a little bit back by seeing where the runtime system spends time during startup. If this includes a significant amount of time checking information that only changes when a plugin is installed or updated (e.g., searching for runtime paths), then we may want to start caching this information in a file that gets updated on updates to save startup time.
- [ ] Simplify `requires`/`wants`/etc.
  - [ ] Unify `requires`/`wants` into `depends_on`: `requires` and `wants` currently duplicate functionality. I propose merging the two into a single keyword `depends_on`, which will (1) ensure that dependencies are installed and (2) ensure that dependencies are loaded before the dependent plugin.
  - [ ] Make interface for `depends_on` and `after` consistent: the correct way to specify dependent plugins/sequential load plugins is confusing, since it's based on a plugin's short name in some cases but the full name in others (I think?). We should define and implement a clear way of referring to plugins in these settings.
- [ ] Clean up interface
  - [ ] Use new Neovim v0.7.0 functions instead of `vim.cmd`: the codebase makes use of a lot of `vim.cmd` with string building for things like generating keymaps, commands, etc. Neovim v0.7.0 introduced the ability to create these directly from Lua, with direct Lua callbacks. `packer` should move to use these functions.
  - [ ] Make management operations sequenceable steps: To clean up and simplify the code for management operations (e.g., installs, updates, cleans, etc.), we want to redesign the operation interface into sequenceable steps (e.g., "check current FS state", "clone missing plugins", "pull installed plugins", etc.) so that the actual operations become a sequence of calls to functions implementing these steps, rather than the current highly-duplicated logic.

## Stage 2: Simplify internal git functions and use of async

The nastiest part of the codebase is the `git` logic.
We would like to simplify this as much as possible.
Also, a significant contributor to the difficulty of working on `packer` is its aggressive use of `async` everywhere.
We should investigate how to minimize the async surface area to allow more flexibility and require less of the codebase to need to think about `async`.

## Stage 3: Issue triage

`packer` has accumulated a large number of outstanding issues.
At this point, we should go through and try to reproduce issues with the updated codebase.
During this process, issues should either be fixed or closed as "Wontfix" or "No longer relevant" unless they are feature requests or questions.
The goal of this stage is to more or less close out the open issues.

## Stage 4: Gradual porting to Teal

Teal offers significant benefits for maintainability and has improved since the last time I took a look at porting `packer`.
After `packer`'s code is at a cleaner, more reliable state, it makes sense to start porting modules incrementally to Teal.

## Stage 5 and onward: new features, Luarocks improvements

Finally, we can start thinking about new features and improvements.
Things like the proposed unified plugin specification format, improvements to Luarocks (e.g., updating rocks, putting binary rocks on the Neovim `PATH`, etc.)
