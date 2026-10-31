#include <lean/lean.h>
#include <sqlite3.h>
#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>

static void finalize_database(void *data) {
    int rc = sqlite3_close_v2(data);
    if (rc != SQLITE_OK)
        fprintf(stderr, "SQLite close failed: %s\n", sqlite3_errstr(rc));
}

static void foreach_database(void *data, b_lean_obj_arg visitor) {
    (void)data;
    (void)visitor;
}

static lean_external_class *database_class;
static pthread_once_t database_class_once = PTHREAD_ONCE_INIT;

static void initialize_database_class(void) {
    database_class = lean_register_external_class(finalize_database, foreach_database);
}

static lean_obj_res fail(const char *message) {
    return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string(message)));
}

LEAN_EXPORT lean_obj_res leanwebstudy_sqlite_open_memory(void) {
    if (pthread_once(&database_class_once, initialize_database_class) != 0)
        return fail("Could not initialize SQLite connection class");
    sqlite3 *db = NULL;
    int rc = sqlite3_open_v2(":memory:", &db,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL);
    if (rc != SQLITE_OK) {
        lean_object *error = fail(db ? sqlite3_errmsg(db) : sqlite3_errstr(rc));
        if (db) sqlite3_close_v2(db);
        return error;
    }
    return lean_io_result_mk_ok(lean_alloc_external(database_class, db));
}

static lean_obj_res statement_error(sqlite3_stmt *stmt, lean_obj_arg rows,
                                    const char *message) {
    lean_object *error = fail(message);
    sqlite3_finalize(stmt);
    lean_dec(rows);
    return error;
}

LEAN_EXPORT lean_obj_res leanwebstudy_sqlite_execute(
    b_lean_obj_arg database, b_lean_obj_arg sql, b_lean_obj_arg params) {
    sqlite3 *db = lean_get_external_data(database);
    sqlite3_stmt *stmt = NULL;
    const char *tail = NULL;
    size_t sql_size = lean_string_size(sql) - 1;
    if (sql_size > INT_MAX || strlen(lean_string_cstr(sql)) != sql_size)
        return fail("SQL must fit in a SQLite statement and contain no NUL bytes");
    int rc = sqlite3_prepare_v2(db, lean_string_cstr(sql), (int)sql_size, &stmt, &tail);
    if (rc != SQLITE_OK) {
        lean_object *error = fail(sqlite3_errmsg(db));
        sqlite3_finalize(stmt);
        return error;
    }
    lean_object *rows = lean_mk_empty_array();
    if (!stmt)
        return statement_error(stmt, rows, "SQL must contain one statement");
    while (*tail == ' ' || *tail == '\n' || *tail == '\r' || *tail == '\t') ++tail;
    if (*tail != '\0')
        return statement_error(stmt, rows, "Only one SQL statement is supported");
    size_t count = lean_array_size(params);
    if (count != (size_t)sqlite3_bind_parameter_count(stmt))
        return statement_error(stmt, rows, "SQL parameter count mismatch");
    for (size_t i = 0; i < count; ++i) {
        lean_object *param = lean_array_get_core(params, i);
        lean_object *value = lean_ctor_get(param, 0);
        if (lean_obj_tag(param) == 0) {
            size_t size = lean_string_size(value) - 1;
            if (size > INT_MAX)
                return statement_error(stmt, rows, "SQL text parameter is too large");
            rc = sqlite3_bind_text(stmt, (int)i + 1, lean_string_cstr(value),
                                   (int)size, SQLITE_TRANSIENT);
        } else {
            rc = sqlite3_bind_int64(stmt, (int)i + 1, (int64_t)lean_int64_of_int(value));
        }
        if (rc != SQLITE_OK)
            return statement_error(stmt, rows, sqlite3_errmsg(db));
    }
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        lean_object *row = lean_mk_empty_array();
        for (int i = 0; i < sqlite3_column_count(stmt); ++i) {
            int type = sqlite3_column_type(stmt, i);
            lean_object *value;
            unsigned tag;
            if (type == SQLITE_INTEGER) {
                tag = 1;
                value = lean_int64_to_int(sqlite3_column_int64(stmt, i));
            } else if (type == SQLITE_TEXT) {
                const unsigned char *text = sqlite3_column_text(stmt, i);
                if (!text) {
                    lean_dec(row);
                    return statement_error(stmt, rows, sqlite3_errmsg(db));
                }
                tag = 0;
                value = lean_mk_string_from_bytes((const char *)text,
                                                  sqlite3_column_bytes(stmt, i));
            } else {
                lean_dec(row);
                return statement_error(stmt, rows,
                    "Unsupported SQLite result type: only INTEGER and TEXT are supported");
            }
            lean_object *cell = lean_alloc_ctor(tag, 1, 0);
            lean_ctor_set(cell, 0, value);
            row = lean_array_push(row, cell);
        }
        rows = lean_array_push(rows, row);
    }
    if (rc != SQLITE_DONE)
        return statement_error(stmt, rows, sqlite3_errmsg(db));
    rc = sqlite3_finalize(stmt);
    if (rc != SQLITE_OK) {
        lean_dec(rows);
        return fail(sqlite3_errmsg(db));
    }
    return lean_io_result_mk_ok(rows);
}
