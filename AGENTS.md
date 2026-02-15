This is an Elixir library/application for serving APT (Debian) repositories. It uses Plug and Bandit for HTTP — it is **not** a Phoenix application.

## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field`
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces. **Never** install additional dependencies unless asked
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason

## Types, specs, and structs

- **Always** define `@type t :: %__MODULE__{}` for every struct
- **Always** add `@spec` annotations to all public functions
- **Always** use proper structs with `defstruct` and `@enforce_keys` instead of bare maps when a data shape is used in more than one place
- **Always** define custom `@type` definitions for complex or recurring data shapes (e.g., `@type metadata :: %{name: String.t(), version: String.t(), ...}`)
- Prefer typed structs over ad-hoc maps for domain concepts

## Documentation

- **Always** add `@moduledoc` to every module explaining its purpose
- **Always** add `@doc` to every public function describing what it does, its parameters, and return values
- Keep docs concise but informative — a one-liner is fine for simple functions

## Testing

- **Always** write unit tests for new public functions
- Place tests in `test/` mirroring the `lib/` directory structure
- Use `describe` blocks to group tests by function
- Test both success and error paths
- Use `setup` blocks to reduce duplication across tests in the same describe block
- Prefer testing through the public API rather than reaching into internals
