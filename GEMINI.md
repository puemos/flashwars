# Project Overview

This project is a web application built with the Phoenix framework for Elixir. It appears to be a learning platform called "Flashwars", likely focused on flashcards and educational games.

The application is built using the Ash framework, a resource-oriented framework for Elixir that provides a high-level abstraction for building applications. The presence of `ash-authentication` suggests user accounts and authentication are a core feature.

The frontend is built using Phoenix LiveView and styled with Tailwind CSS. The use of `esbuild` indicates a modern JavaScript toolchain.

The application uses a PostgreSQL database, as indicated by the `postgrex` dependency and the `Flashwars.Repo` module.

Background jobs are handled by Oban, a robust job processing library for Elixir.

## Building and Running

To get the application running locally, follow these steps:

1.  **Install dependencies:**
    ```bash
    mix setup
    ```

2.  **Start the Phoenix server:**
    ```bash
    mix phx.server
    ```

The application should now be running at [http://localhost:4000](http://localhost:4000).

### Testing

To run the test suite, use the following command:

```bash
mix test
```

## Development Conventions

The project follows standard Elixir and Phoenix conventions.

*   **Code Formatting:** The project uses the standard Elixir formatter. To format the code, run:
    ```bash
    mix format
    ```
*   **Linting:** The project has a `precommit` alias that runs a compiler check with warnings as errors, checks for unused dependencies, formats the code, and runs the test suite. To run the pre-commit checks, use:
    ```bash
    mix precommit
    ```

## Key Technologies

*   **Backend:** Elixir, Phoenix, Ash Framework
*   **Frontend:** Phoenix LiveView, Tailwind CSS, JavaScript (with esbuild)
*   **Database:** PostgreSQL
*   **Background Jobs:** Oban

## Project Structure

The project is organized into several Ash domains, each representing a different context of the application:

*   `Flashwars.Accounts`: User accounts and authentication.
*   `Flashwars.Content`: Content management, likely for flashcards and other learning materials.
*   `Flashwars.Org`: Organizational features, possibly for schools or other institutions.
*   `Flashwars.Classroom`: Classroom management features.
*   `Flashwars.Learning`: Core learning logic and functionality.
*   `Flashwars.Games`: Educational games.
*   `Flashwars.Ops`: Operational tasks and administration.
