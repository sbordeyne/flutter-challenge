# Todo Backend

A simple backend server for technical tests in dart. Backed by an in-container sqlite3 database for simplicity

## Running

You will need to have `docker` and GNU `make` installed.

Simply run `make run` to run the backend.
The server will start listening on port `8080`.

You can stop the server at any time with `Ctrl + C` (`SIGINT` signal)

## Assignment

Your goal is to develop an app in the `flutter` framework to handle "TODOs". This app should, in its MVP:

- Allow you to see all the TODOs
- Allow you to see a specific TODO in full screen
- Allow you to create TODOs
- Allow you to edit TODOs, in a dialog
- Allow you to delete individual todos

Feel free to implement any and all features you might think is pertinent to such an app,
a successful GET /1 response looks like:

```json
{
    "id": 1,
    "title": "Test TODO",
    "body": null,
    "file": null,
    "metadata": null,
    "priority": 1,
    "created_at": "2024-08-19T16:59:15.594295",
    "updated_at": "2024-08-19T16:59:15.594295",
    "completed_at": null // or datetime
}
```

A successful create request for a completed todo looks like this

```json
{
    "title": "Test TODO",
    "completed": true,
    "metadata": {
        "test": "olt"
    }
}
```

The API supports the following features:

- GET, POST, PATCH, DELETE verbs
- If-None-Match / ETag headers on requests/responses
- CORS
- List filters in query params on GET requests
- Batch creation of TODOs
- Raw SQL queries from the API

### Available filters

- is_completed: true/false => whether a todo is done
- title_contains: string => checks the title
- body_contains: string => checks the body
- has_file: true/false => whether a file is attached
- created_before/created_after: datetime => created before / after a certain date
- updated_before/updated_after: datetime => updated before / after a certain date
- completed_before/completed_after: datetime => completed before / after a certain date
- priority: int => priority equals
- priority_gt / gte / lt / lte: priority greater than, greater than or equals and so on

All filters are are ANDed together.
