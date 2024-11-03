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
