/*******************************************************************************
 * Internal misc functions
 */
module bsky._internal.misc;

package(bsky):

import std.json: JSONValue;
import std.datetime: SysTime;
import std.traits;
import bsky._internal.json: converter;

/*******************************************************************************
 * SysTime converter user data attribute
 */
enum systimeConverter = converter!SysTime(
	jv=>SysTime.fromISOExtString(jv.str),
	v =>JSONValue(v.toISOExtString()));


version (unittest) package(bsky) T readDataSource(T = immutable(ubyte)[])(string fileName) @trusted
{
	import std.file, std.path;
	return cast(T)std.file.read("tests/.ut-data_source".buildPath(fileName));
}

version (unittest) package(bsky) T readDataSource(T: string)(string fileName) @trusted
{
	import std.file, std.path;
	return std.file.readText("tests/.ut-data_source".buildPath(fileName));
}

version (unittest) package(bsky) T readDataSource(T: JSONValue)(string fileName) @trusted
{
	import std.json;
	return readDataSource!string(fileName).parseJSON();
}

void convine(ref JSONValue rhs, in JSONValue lhs) @trusted
{
	import std.json, std.exception;
	if (rhs.type == JSONType.object && lhs.type == JSONType.object)
	{
		foreach (ref k, ref v; lhs.object)
		{
			if (auto p = k in rhs.object)
			{
				// 左にあって右にもある場合、さらに両者を結合
				convine(*p, v);
			}
			else
			{
				// 左にあって右にない場合、右に新規作成
				rhs[k] = v;
			}
		}
	}
	else if (rhs.type == JSONType.array && lhs.type == JSONType.array)
	{
		foreach (i; 0..lhs.array.length)
		{
			// 左にあって右にもある場合、さらに両者を結合
			if (i < rhs.array.length)
			{
				convine(rhs.array[i], lhs.array[i]);
			}
			else
			{
				// 左にあって右にない場合、右に新規作成
				rhs.array ~= lhs.array[i];
			}
		}
	}
	else
	{
		// オブジェクトでも配列でもない場合、上書き
		rhs = lhs;
	}
}

@safe unittest
{
	auto jv1 = JSONValue([
		"test": JSONValue("value"),
		"test2": JSONValue(["test3": "value3", "testtest": "testtestA"]),
		"test5": JSONValue([1, 2, 3]),
		"test6": JSONValue(42)]);
	auto jv2 = JSONValue([
		"test1": JSONValue("value1"),
		"test2": JSONValue(["test4": "value4", "testtest": "testtestB"]),
		"test5": JSONValue([4, 5, 6, 7]),
		"test6": JSONValue("value6")]);
	jv1.convine(jv2);
	assert(jv1["test"].str == "value");
	assert(jv1["test1"].str == "value1");
	assert(jv1["test2"]["test3"].str == "value3");
	assert(jv1["test2"]["test4"].str == "value4");
	assert(jv1["test2"]["testtest"].str == "testtestB");
	assert(jv1["test5"].arrayNoRef.length == 4);
	assert(jv1["test5"][1].get!int == 5);
	assert(jv1["test5"][3].get!int == 7);
	assert(jv1["test6"].str == "value6");
}
