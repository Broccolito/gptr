# Schema validation, coercion and signatures (Task 12).

r_schema = list(
  type = "object",
  required = I("code"),
  properties = list(
    code = list(type = "string", description = "R code to run."),
    record = list(type = "boolean"),
    timeout = list(type = "integer"),
    tags = list(type = "array", items = list(type = "string")),
    mode = list(type = "string", enum = c("fast", "slow"))
  )
)

test_that("a missing required property is an error naming it (05 P01 acceptance 4)", {
  res = schema_validate(r_schema, json_decode("{\"n\":3}"))
  expect_false(res$ok)
  expect_length(res$errors, 1L)
  expect_match(res$errors, "'code'", fixed = TRUE)
  expect_identical(res$input$n, 3L)
})

test_that("valid input passes with the documented coercions only", {
  res = schema_validate(r_schema, list(code = "1 + 1", timeout = 30, tags = "a", record = TRUE))
  expect_true(res$ok)
  expect_identical(res$input$timeout, 30L)
  expect_identical(res$input$tags, list("a"))
  expect_identical(res$input$code, "1 + 1")
})

test_that("type, enum and integer errors are reported with the property path", {
  res = schema_validate(r_schema, list(code = 1, timeout = 2.5, mode = "medium", record = "yes"))
  expect_false(res$ok)
  expect_length(res$errors, 4L)
  expect_true(any(grepl("'code' must be string", res$errors, fixed = TRUE)))
  expect_true(any(grepl("'timeout' must be integer", res$errors, fixed = TRUE)))
  expect_true(any(grepl("'mode' must be one of", res$errors, fixed = TRUE)))
  expect_true(any(grepl("'record' must be boolean", res$errors, fixed = TRUE)))
})

test_that("unknown properties are kept unless additionalProperties is false", {
  expect_true(schema_validate(r_schema, list(code = "x", extra = 1))$ok)
  strict = c(r_schema, list(additionalProperties = FALSE))
  res = schema_validate(strict, list(code = "x", extra = 1))
  expect_false(res$ok)
  expect_match(res$errors, "unknown property 'extra'", fixed = TRUE)
})

test_that("nested objects and array items are validated", {
  schema = list(type = "object", properties = list(
    edits = list(type = "array", items = list(
      type = "object", required = I(c("old", "new")),
      properties = list(old = list(type = "string"), new = list(type = "string"))
    ))
  ))
  res = schema_validate(schema, json_decode("{\"edits\":[{\"old\":\"a\"}]}"))
  expect_false(res$ok)
  expect_match(res$errors, "missing required property 'edits[1].new'", fixed = TRUE)
  expect_true(schema_validate(schema, NULL)$ok)
  expect_true(schema_validate(list(type = c("string", "null")), NULL)$ok)
})

test_that("schema_signature() renders one line with optional markers and the first sentence", {
  expect_identical(
    schema_signature("r", r_schema, "Run R code in the session. It returns output."),
    paste0(
      "r(code: string, record?: boolean, timeout?: integer, tags?: array, mode?: string)",
      "  # Run R code in the session."
    )
  )
  expect_identical(
    schema_signature("grep", list(type = "object"), prefix = "peter$"), "peter$grep()"
  )
})

test_that("schema_problems() finds structural mistakes", {
  expect_identical(schema_problems(r_schema), character())
  problems = schema_problems(list(
    type = "objekt",
    properties = list(a = list(type = "string")),
    required = I(c("a", "b"))
  ))
  expect_length(problems, 2L)
  expect_true(any(grepl("type must be one of", problems, fixed = TRUE)))
  expect_true(any(grepl("'b' is not in properties", problems, fixed = TRUE)))
  expect_match(schema_problems(list(1, 2)), "named list", fixed = TRUE)
})

test_that("object constraints apply to object instances under union types", {
  required = list(type = c("object", "null"), required = "code")
  missing = schema_validate(required, json_obj())
  expect_false(missing$ok)
  expect_match(missing$errors, "missing required property 'code'", fixed = TRUE)
  expect_true(schema_validate(required, list(code = "x"))$ok)
  strict = list(type = c("object", "null"), additionalProperties = FALSE)
  expect_false(schema_validate(strict, list(extra = 1))$ok)
  expect_true(schema_validate(strict, json_obj())$ok)
})

test_that("nullable object schemas preserve explicit null inputs", {
  schema = list(type = c("object", "null"), required = "x",
                properties = list(x = list(type = "string")))
  res = schema_validate(schema, NULL)
  expect_true(res$ok)
  expect_null(res$input)
  expect_identical(res$errors, character())
  expect_false(schema_validate(schema, json_obj())$ok)
  expect_true(schema_validate(list(type = "object"), NULL)$ok)
})

test_that("empty JSON objects and arrays retain distinct schema types", {
  empty_object = structure(list(), names = character())
  expect_true(schema_validate(list(type = "object"), empty_object)$ok)
  expect_true(schema_validate(list(type = "object"), json_decode("{}"))$ok)
  expect_false(schema_validate(list(type = "object"), json_decode("[]"))$ok)
  expect_true(schema_validate(list(type = "array"), json_decode("[]"))$ok)
  expect_false(schema_validate(list(type = "array"), empty_object)$ok)
})

test_that("enum comparisons preserve JSON scalar types", {
  expect_false(schema_validate(list(enum = 1), "1")$ok)
  expect_false(schema_validate(list(enum = TRUE), 1)$ok)
  expect_false(schema_validate(list(enum = "true"), TRUE)$ok)
  expect_true(schema_validate(list(enum = 1L), 1)$ok)
  expect_true(schema_validate(list(enum = 1), 1L)$ok)
  mixed = list(enum = list(1, TRUE, "yes", NULL))
  expect_true(schema_validate(mixed, TRUE)$ok)
  expect_true(schema_validate(mixed, NULL)$ok)
  expect_false(schema_validate(mixed, "1")$ok)
})

test_that("enum comparisons preserve nested objects, arrays and null", {
  schema = json_decode('{"enum":[{"a":[1,2],"b":true},[1,2],null,{},[]]}')
  expect_true(schema_validate(schema, list(b = TRUE, a = list(1, 2)))$ok)
  expect_true(schema_validate(schema, list(1L, 2L))$ok)
  expect_true(schema_validate(schema, NULL)$ok)
  expect_true(schema_validate(schema, json_obj())$ok)
  expect_true(schema_validate(schema, list())$ok)
  expect_false(schema_validate(schema, list(a = list("1", 2), b = TRUE))$ok)
  expect_false(schema_validate(schema, list(2L, 1L))$ok)
  expect_false(schema_validate(list(enum = list(json_obj())), list())$ok)
  expect_false(schema_validate(list(enum = list(list())), json_obj())$ok)
  expect_identical(schema_problems(list(enum = list(NULL))), character())
  expect_true(schema_validate(list(enum = list(NULL)), NULL)$ok)
})

test_that("JSON number validation rejects non-finite and complex values", {
  for (value in list(Inf, -Inf, NaN, 1 + 1i, json_decode("1e999"))) {
    expect_false(schema_validate(list(type = "number"), value)$ok)
  }
  expect_true(schema_validate(list(type = "number"), 1e300)$ok)
  expect_false(schema_validate(list(enum = Inf), Inf)$ok)
})
