-- tests/run.lua
-- Minimal test runner. From the repository root:
--   lua5.1 tests/run.lua tests/test_*.lua
-- Test files register cases with testing.test(name, fn); a case fails when it
-- raises. The exit status is non-zero when a case fails or none was found.

local testsDir = arg[0]:match("^(.*)[/\\]") or "."
package.path = testsDir .. "/?.lua;" .. package.path

local testing = { cases = {} }
package.loaded.testing = testing

local currentFile

function testing.test(name, fn)
	testing.cases[#testing.cases + 1] = { file = currentFile, name = name, fn = fn }
end

local function Describe(value)
	if type(value) == "table" and getmetatable(value) == "secret" then return "<secret>" end
	if type(value) == "string" then return string.format("%q", value) end
	return tostring(value)
end

local function Fail(message, detail)
	error((message and message .. ": " or "") .. detail, 3)
end

function testing.equal(actual, expected, message)
	if actual ~= expected then
		Fail(message, "expected " .. Describe(expected) .. ", got " .. Describe(actual))
	end
end

function testing.truthy(value, message)
	if not value then
		Fail(message, "expected a truthy value, got " .. Describe(value))
	end
end

function testing.contains(text, fragment, message)
	if type(text) ~= "string" or not text:find(fragment, 1, true) then
		Fail(message, "expected " .. Describe(text) .. " to contain " .. Describe(fragment))
	end
end

function testing.excludes(text, fragment, message)
	if type(text) ~= "string" or text:find(fragment, 1, true) then
		Fail(message, "expected " .. Describe(text) .. " not to contain " .. Describe(fragment))
	end
end

for i = 1, #arg do
	currentFile = arg[i]:match("([^/\\]+)$")
	dofile(arg[i])
end

local failed = 0
for _, case in ipairs(testing.cases) do
	local ok, err = xpcall(case.fn, debug.traceback)
	local label = case.file .. ": " .. case.name
	if ok then
		print("ok   " .. label)
	else
		failed = failed + 1
		local details = tostring(err):gsub("\n", "\n     ")
		print("FAIL " .. label .. "\n     " .. details)
	end
end

print(string.format("\n%d passed, %d failed", #testing.cases - failed, failed))
if #testing.cases == 0 then
	print("no test cases found")
	os.exit(1)
end
os.exit(failed == 0 and 0 or 1)
