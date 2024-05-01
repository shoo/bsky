/*******************************************************************************
 * Internal JSON helpers
 */
module bsky._internal.json;

package(bsky):

version (Have_voile) {
	public import voile.json;
}
else:



import std.json, std.traits, std.meta, std.conv, std.array;
import std.typecons: Rebindable;
import std.sumtype: SumType, isSumType;
import std.typecons: Tuple;
import bsky._internal.attr;
import bsky._internal.misc;


/*******************************************************************************
 * JSONValueデータを得る
 */
JSONValue json(T)(auto const ref T[] x) @property
if (isSomeString!(T[]))
{
	return JSONValue(to!string(x));
}
///
@system unittest
{
	dstring dstr = "あいうえお";
	wstring wstr = "かきくけこ";
	string  str  = "さしすせそ";
	auto dstrjson = dstr.json;
	auto wstrjson = wstr.json;
	auto strjson  = str.json;
	assert(dstrjson.type == JSONType.string);
	assert(wstrjson.type == JSONType.string);
	assert(strjson.type  == JSONType.string);
	assert(dstrjson.str == "あいうえお");
	assert(wstrjson.str == "かきくけこ");
	assert(strjson.str  == "さしすせそ");
}


/// ditto
JSONValue json(T)(auto const ref T x) @property
if ((isIntegral!T && !is(T == enum))
 || isFloatingPoint!T
 || is(Unqual!T == bool))
{
	return JSONValue(x);
}
///
@system unittest
{
	bool bt = true;
	bool bf;
	auto btjson = bt.json;
	auto bfjson = bf.json;
	assert(btjson.type == JSONType.true_);
	assert(bfjson.type == JSONType.false_);
}
///
@system unittest
{
	import std.typetuple;
	foreach (T; TypeTuple!(ubyte, byte, ushort, short, uint, int, ulong, long))
	{
		T x = 123;
		auto xjson = x.json;
		static if (isUnsigned!T)
		{
			assert(xjson.type == JSONType.uinteger);
			assert(xjson.uinteger == 123);
		}
		else
		{
			assert(xjson.type == JSONType.integer);
			assert(xjson.integer == 123);
		}
	}
	foreach (T; TypeTuple!(float, double, real))
	{
		T x = 0.125;
		auto xjson = x.json;
		assert(xjson.type == JSONType.float_);
		assert(xjson.floating == 0.125);
	}
}

/// ditto
JSONValue json(T)(auto const ref T x) @property
if (is(T == enum))
{
	return JSONValue(x.to!string());
}
///
@system unittest
{
	enum EnumType
	{
		a, b, c
	}
	auto a = EnumType.a;
	auto ajson = a.json;
	assert(ajson.type == JSONType.string);
	assert(ajson.str == "a");
}

/// ditto
JSONValue json(T)(auto const ref T[] ary) @property
if (!isSomeString!(T[]) && isArray!(T[]))
{
	auto app = appender!(JSONValue[])();
	JSONValue v;
	foreach (x; ary)
	{
		app.put(x.json);
	}
	v.array = app.data;
	return v;
}
///
@system unittest
{
	auto ary = [1,2,3];
	auto aryjson = ary.json;
	assert(aryjson.type == JSONType.array);
	assert(aryjson[0].type == JSONType.integer);
	assert(aryjson[1].type == JSONType.integer);
	assert(aryjson[2].type == JSONType.integer);
	assert(aryjson[0].integer == 1);
	assert(aryjson[1].integer == 2);
	assert(aryjson[2].integer == 3);
}
///
@system unittest
{
	auto ary = ["ab","cd","ef"];
	auto aryjson = ary.json;
	assert(aryjson.type == JSONType.array);
	assert(aryjson[0].type == JSONType.string);
	assert(aryjson[1].type == JSONType.string);
	assert(aryjson[2].type == JSONType.string);
	assert(aryjson[0].str == "ab");
	assert(aryjson[1].str == "cd");
	assert(aryjson[2].str == "ef");
}

///
@system unittest
{
	struct A
	{
		int a = 123;
		JSONValue json() const @property
		{
			return JSONValue(["a": JSONValue(a)]);
		}
		void json(JSONValue v) @property
		{
			a = v.getValue("a", 123);
		}
	}
	auto ary = [A(1),A(2),A(3)];
	auto aryjson = ary.json;
	assert(aryjson.type == JSONType.array);
	assert(aryjson[0].type == JSONType.object);
	assert(aryjson[1].type == JSONType.object);
	assert(aryjson[2].type == JSONType.object);
	assert(aryjson[0]["a"].type == JSONType.integer);
	assert(aryjson[1]["a"].type == JSONType.integer);
	assert(aryjson[2]["a"].type == JSONType.integer);
	assert(aryjson[0]["a"].integer == 1);
	assert(aryjson[1]["a"].integer == 2);
	assert(aryjson[2]["a"].integer == 3);
}

/// ditto
JSONValue json(Value, Key)(auto const ref Value[Key] aa) @property
if (isSomeString!Key && is(typeof({auto v = Value.init.json;})))
{
	auto ret = JSONValue((JSONValue[string]).init);
	static if (is(Key: const string))
	{
		foreach (key, val; aa)
			ret.object[key] = val.json;
	}
	else
	{
		foreach (key, val; aa)
			v.object[key.to!string] = val.json;
	}
	return ret;
}
///
@system unittest
{
	int[string] val;
	val["xxx"] = 10;
	auto jv = val.json;
	assert(jv["xxx"].integer == 10);
}


/// ditto
JSONValue json(JV)(auto const ref JV v) @property
	if (is(JV: const JSONValue))
{
	return cast(JSONValue)v;
}


private void _setValue(T)(ref JSONValue v, ref string name, ref T val)
	if (is(typeof(val.json)))
{
	if (v.type != JSONType.object || !v.object)
	{
		v = [name: val.json];
	}
	else
	{
		auto x = v.object;
		x[name] = val.json;
		v = x;
	}
}


/*******************************************************************************
 * JSONValueデータの操作
 */
void setValue(T)(ref JSONValue v, string name, T val) pure nothrow @trusted
{
	try
	{
		assumePure!(_setValue!T)(v, name, val);
	}
	catch (Throwable)
	{
	}
}

///
@system unittest
{
	JSONValue json;
	json.setValue("dat", 123);
	assert(json.type == JSONType.object);
	assert("dat" in json.object);
	assert(json["dat"].type == JSONType.integer);
	assert(json["dat"].integer == 123);
}



///
@system unittest
{
	enum Type
	{
		foo, bar,
	}
	JSONValue json;
	json.setValue("type", Type.foo);
	assert(json.type == JSONType.object);
	assert("type" in json.object);
	assert(json["type"].type == JSONType.string);
	assert(json["type"].str == "foo");
}

///
@system unittest
{
	struct A
	{
		int a = 123;
		JSONValue json() const @property
		{
			JSONValue v;
			v.setValue("a", a);
			return v;
		}
	}
	A a;
	a.a = 321;
	JSONValue json;
	json.setValue("a", a);
}


///
@system unittest
{
	JSONValue json;
	json.setValue("test", "あいうえお");
	static assert(is(typeof(json.getValue("test", "かきくけこ"d)) == dstring));
	static assert(is(typeof(json.getValue("test", "かきくけこ"w)) == wstring));
	static assert(is(typeof(json.getValue("test", "かきくけこ"c)) == string));
	assert(json.getValue("test", "かきくけこ"d) == "あいうえお"d);
	assert(json.getValue("test", "かきくけこ"w) == "あいうえお"w);
	assert(json.getValue("test", "かきくけこ"c) == "あいうえお"c);
	assert(json.getValue("hoge", "かきくけこ"c) == "かきくけこ"c);
}


///
bool fromJson(T)(in JSONValue src, ref T dst)
if (isSomeString!T)
{
	if (src.type == JSONType.string)
	{
		static if (is(T: string))
		{
			dst = src.str;
		}
		else
		{
			dst = to!T(src.str);
		}
		return true;
	}
	return false;
}
///
@system unittest
{
	auto jv = JSONValue("xxx");
	string dst;
	auto res = fromJson(jv, dst);
	assert(res);
	assert(dst == "xxx");
}


/// ditto
bool fromJson(T)(in JSONValue src, ref T dst)
	if (isIntegral!T && !is(T == enum))
{
	if (src.type == JSONType.integer)
	{
		dst = cast(T)src.integer;
		return true;
	}
	else if (src.type == JSONType.uinteger)
	{
		dst = cast(T)src.uinteger;
		return true;
	}
	return false;
}
///
@system unittest
{
	auto jv = JSONValue(10);
	int dst;
	auto res = fromJson(jv, dst);
	assert(res);
	assert(dst == 10);
}

/// ditto
bool fromJson(T)(in JSONValue src, ref T dst)
	if (isFloatingPoint!T)
{
	switch (src.type)
	{
	case JSONType.float_:
		dst = cast(T)src.floating;
		return true;
	case JSONType.integer:
		dst = cast(T)src.integer;
		return true;
	case JSONType.uinteger:
		dst = cast(T)src.uinteger;
		return true;
	default:
		return false;
	}
}
///
@system unittest
{
	import std.math: isClose;
	auto jv = JSONValue(10.0);
	double dst;
	auto res = fromJson(jv, dst);
	assert(res);
	assert(dst.isClose(10.0));
}

/// ditto
bool fromJson(T)(in JSONValue src, ref T dst)
if (is(T == struct)
 && !is(Unqual!T: JSONValue))
{
	static if (__traits(compiles, { dst.json = src; }))
	{
		dst.json = src;
	}
	else static foreach (memberIdx, member; T.tupleof)
	{{
		static if (!hasIgnore!member)
		{
			static if (hasName!member)
			{
				enum fieldName = getName!member;
			}
			else
			{
				enum fieldName = __traits(identifier, member);
			}
			static if (hasConvBy!member)
			{
				static if (hasEssential!member)
				{
					dst.tupleof[memberIdx] = convFrom!(member, JSONValue)(src[fieldName]);
				}
				else
				{
					if (auto pJsonValue = fieldName in src)
					{
						try
							dst.tupleof[memberIdx] = convFrom!(member, JSONValue)(*pJsonValue);
						catch (Exception e)
						{
							/* ignore */
						}
					}
				}
			}
			else static if (__traits(compiles, fromJson(src[fieldName], dst.tupleof[memberIdx])))
			{
				static if (hasEssential!member)
				{
					if (!fromJson(src[fieldName], dst.tupleof[memberIdx]))
						return false;
				}
				else
				{
					import std.algorithm: move;
					auto tmp = src.getValue(fieldName, dst.tupleof[memberIdx]);
					move(tmp, dst.tupleof[memberIdx]);
				}
			}
			else
			{
				return false;
			}
		}
	}}
	return true;
}
///
@system unittest
{
	auto jv = JSONValue(["x": 10, "y": 20]);
	static struct Point{ int x, y; }
	Point pt;
	auto res = fromJson(jv, pt);
	assert(res);
	assert(pt.x == 10);
	assert(pt.y == 20);
}

/// ditto
bool fromJson(T)(in JSONValue src, ref T dst)
if (is(T == class))
{
	if (src.type == JSONType.object)
	{
		if (!dst)
			dst = new T;
		dst.json = src;
		return true;
	}
	return false;
}

/// ditto
bool fromJson(T)(in JSONValue src, ref T dst)
	if (is(T == enum))
{
	if (src.type == JSONType.string)
	{
		dst = to!T(src.str);
		return true;
	}
	return false;
}

/// ditto
bool fromJson(T)(in JSONValue src, ref T dst)
	if (is(T == bool))
{
	if (src.type == JSONType.true_)
	{
		dst = true;
		return true;
	}
	else if (src.type == JSONType.false_)
	{
		dst = false;
		return true;
	}
	return false;
}

/// ditto
bool fromJson(T)(in JSONValue src, ref T dst)
	if (!isSomeString!(T) && isDynamicArray!(T))
{
	alias E = ForeachType!T;
	if (src.type == JSONType.array)
	{
		dst = (dst.length >= src.array.length) ? dst[0..src.array.length]: new E[src.array.length];
		foreach (ref i, ref e; src.array)
		{
			if (!fromJson(e, dst[i]))
				return false;
		}
		return true;
	}
	return false;
}

/// ditto
bool fromJson(Value, Key)(in JSONValue src, ref Value[Key] dst)
	if (isSomeString!Key && is(typeof({ JSONValue val; cast(void)fromJson(val, dst[Key.init]); })))
{
	if (src.type == JSONType.object)
	{
		foreach (key, ref val; src.object)
		{
			static if (is(Key: const string))
			{
				Value tmp;
				if (!fromJson(val, tmp))
					return false;
				dst[key] = tmp;
			}
			else
			{
				Value tmp;
				if (!fromJson(val, tmp))
					return false;
				dst[to!Key(key)] = tmp;
			}
		}
		return true;
	}
	return false;
}

/// ditto
bool fromJson(T)(in JSONValue src, ref T dst)
	if (is(Unqual!T == JSONValue))
{
	dst = src;
	return true;
}


private T _getValue(T)(in JSONValue v, string name, lazy scope T defaultVal = T.init)
{
	if (auto x = name in v.object)
	{
		static if (is(T == struct)
		        && !is(Unqual!T: JSONValue)
		        && __traits(compiles, lvalueOf!T.json(rvalueOf!JSONValue)))
		{
			auto ret = T.init;
			ret.json = *x;
			return ret;
		}
		else static if (is(T == class))
		{
			auto ret = new T;
			ret.json = *x;
			return ret;
		}
		else static if (!isSomeString!(T) && isDynamicArray!(T))
		{
			Unqual!(ForeachType!T)[] tmp;
			return fromJson(*x, tmp) ? cast(T)tmp : defaultVal;
		}
		else
		{
			T tmp;
			return fromJson(*x, tmp) ? tmp : defaultVal;
		}
	}
	return defaultVal;
}

///
T getValue(T)(in JSONValue v, string name, lazy scope T defaultVal = T.init) nothrow pure @trusted
{
	import bsky._internal.misc: assumePure;
	try
	{
		return assumePure(&_getValue!(Unqual!T))(v, name, defaultVal);
	}
	catch(Throwable)
	{
	}
	try
	{
		return defaultVal;
	}
	catch (Throwable)
	{
	}
	return T.init;
}


///
@system unittest
{
	JSONValue json;
	json.setValue("test", 123);
	static assert(is(typeof(json.getValue("test", 654UL)) == ulong));
	static assert(is(typeof(json.getValue("test", 654U)) == uint));
	static assert(is(typeof(json.getValue("test", cast(byte)12)) == byte));
	assert(json.getValue("test", 654UL) == 123);
	assert(json.getValue("test", 654U) == 123);
	assert(json.getValue("test", cast(byte)12) == 123);
	assert(json.getValue("hoge", cast(byte)12) == 12);
}


///
@system unittest
{
	JSONValue json;
	json.setValue("test", 0.125);
	static assert(is(typeof(json.getValue("test", 0.25f)) == float));
	static assert(is(typeof(json.getValue("test", 0.25)) == double));
	static assert(is(typeof(json.getValue("test", 0.25L)) == real));
	assert(json.getValue("test", 0.25f) == 0.125f);
	assert(json.getValue("test", 0.25) == 0.125);
	assert(json.getValue("test", 0.25L) == 0.125L);
	assert(json.getValue("hoge", 0.25L) == 0.25L);
}


///
@system unittest
{
	struct A
	{
		int a = 123;
		JSONValue json() const @property
		{
			JSONValue v;
			v.setValue("a", a);
			return v;
		}
		void json(JSONValue v) @property
		{
			a = v.getValue("a", 123);
		}
	}
	A a;
	a.a = 321;
	JSONValue json;
	json.setValue("a", a);
	static assert(is(typeof(json.getValue("a", A(456))) == A));
	assert(json.getValue("a", A(456)).a == 321);
	assert(json.getValue("b", A(456)).a == 456);
}


///
@system unittest
{
	static class A
	{
		int a = 123;
		JSONValue json() const @property
		{
			JSONValue v;
			v.setValue("a", a);
			return v;
		}
		void json(JSONValue v) @property
		{
			a = v.getValue("a", 123);
		}
	}
	auto a = new A;
	a.a = 321;
	JSONValue json;
	json.setValue("a", a);
	static assert(is(typeof(json.getValue!A("a")) == A));
	assert(json.getValue!A("a").a == 321);
	assert(json.getValue!A("b") is null);
}


///
@system unittest
{
	enum Type
	{
		foo, bar
	}
	JSONValue json;
	json.setValue("a", Type.bar);
	static assert(is(typeof(json.getValue("a", Type.foo)) == Type));
	assert(json.getValue("a", Type.foo) == Type.bar);
	assert(json.getValue("b", Type.foo) == Type.foo);
}


///
@system unittest
{
	JSONValue json;
	json.setValue("t", true);
	json.setValue("f", false);
	static assert(is(typeof(json.getValue("t", true)) == bool));
	static assert(is(typeof(json.getValue("f", false)) == bool));
	assert(json.getValue("t", true) == true);
	assert(json.getValue("f", true) == false);
	assert(json.getValue("t", false) == true);
	assert(json.getValue("f", false) == false);
	assert(json.getValue("x", true) == true);
	assert(json.getValue("x", false) == false);
}


///
@system unittest
{
	JSONValue json;
	json.setValue("test1", [1,2,3]);
	auto x = json.getValue("test1", [2,3,4]);
	
	static assert(is(typeof(json.getValue("test1", [2,3,4])) == int[]));
	assert(json.getValue("test1", [2,3,4]) == [1,2,3]);
	assert(json.getValue("test1x", [2,3,4]) == [2,3,4]);
	
	json.setValue("test2", [0.5,0.25,0.125]);
	static assert(is(typeof(json.getValue("test2", [0.5,0.5,0.5])) == double[]));
	assert(json.getValue("test2", [0.5,0.5,0.5]) == [0.5,0.25,0.125]);
	assert(json.getValue("test2x", [0.5,0.5,0.5]) == [0.5,0.5,0.5]);
	
	json.setValue("test3", ["ab","cd","ef"]);
	static assert(is(typeof(json.getValue("test3", ["あい","うえ","おか"])) == string[]));
	assert(json.getValue("test3", ["あい","うえ","おか"]) == ["ab","cd","ef"]);
	assert(json.getValue("test3x", ["あい","うえ","おか"]) == ["あい","うえ","おか"]);
	
	json.setValue("test4", [true, false, true]);
	static assert(is(typeof(json.getValue("test4", [false, true, true])) == bool[]));
	assert(json.getValue("test4", [false, true, true]) == [true, false, true]);
	assert(json.getValue("test4x", [false, true, true]) == [false, true, true]);
}


///
@system unittest
{
	static struct A
	{
		int a = 123;
		JSONValue json() const @property
		{
			JSONValue v;
			v.setValue("a", a);
			return v;
		}
		void json(JSONValue v) @property
		{
			assert(v.type == JSONType.object);
			a = v.getValue("a", 123);
		}
	}
	auto a = [A(1),A(2),A(3)];
	JSONValue json;
	json.setValue("a", a);
	static assert(is(typeof(json.getValue("a", [A(4),A(5),A(6)])) == A[]));
	assert(json.getValue("a", [A(4),A(5),A(6)]) == [A(1),A(2),A(3)]);
	assert(json.getValue("b", [A(4),A(5),A(6)]) == [A(4),A(5),A(6)]);
}



///
alias JSONValueArray  = Rebindable!(const(JSONValue[]));
///
alias JSONValueObject = Rebindable!(const(JSONValue[string]));

/*******************************************************************************
 * 
 */
bool getArray(JSONValue json, string name, ref JSONValueArray ary)
{
	if (json.type != JSONType.object)
		return false;
	if (auto p = name in json)
	{
		if (p.type != JSONType.array)
			return false;
		ary = p.array;
		return true;
	}
	return false;
}

/*******************************************************************************
 * 
 */
bool getObject(JSONValue json, string name, ref JSONValueObject object)
{
	if (json.type != JSONType.object)
		return false;
	if (auto p = name in json)
	{
		if (p.type != JSONType.object)
			return false;
		object = p.object;
		return true;
	}
	return false;
}

///
struct AttrConverter(T)
{
	///
	T function(in JSONValue v) from;
	///
	JSONValue function(in T v) to;
}

/*******************************************************************************
 * Attribute converting method
 */
AttrConverter!T converter(T)(T function(in JSONValue) from, JSONValue function(in T) to)
{
	return AttrConverter!T(from, to);
}




private enum isJSONizableRaw(T) = is(typeof({
	T val;
	JSONValue jv= val.json;
	cast(void)fromJson(jv, val);
}));

//
private template uniqueKey(ST, string name, uint num = 0)
if (isSumType!ST)
{
	enum string candidate = num == 0 ? name : text(name, num);
	
	static if (anySatisfy!(ApplyRight!(hasMember, candidate), ST.Types))
	{
		enum string uniqueKey = uniqueKey!(ST, name, num+1);
	}
	else
	{
		enum string uniqueKey = candidate;
	}
}


private bool _isNotEq(string[] rhs, string[] lhs) @safe
{
	import std.algorithm: canFind;
	bool ret = true;
	foreach (k; rhs)
		ret &= lhs.canFind(k);
	return !ret;
}
@safe unittest
{
	assert(_isNotEq(["a", "b"], ["a", "c"]));
	assert(!_isNotEq(["a", "b"], ["a", "b"]));
	assert(!_isNotEq(["a", "b"], ["b", "a"]));
}
private bool _isUniq(string[] keyMembers, string[][] anotherKeyMembers) @safe
{
	bool ret = true;
	foreach (keys; anotherKeyMembers)
		ret &= _isNotEq(keyMembers, keys);
	return ret;
}
@safe unittest
{
	assert(_isUniq(["a", "b"], [["a", "c"], ["a", "d"]]));
	assert(!_isUniq(["a", "b"], [["a", "b"], ["a", "d"]]));
	assert(!_isUniq(["a", "b"], [["b", "a"], ["a", "d"]]));
}
private bool _isAllUniq(string[][] keyMembers) @safe
{
	bool ret = true;
	foreach (idx; 0..keyMembers.length)
		ret &= _isUniq(keyMembers[idx], keyMembers[idx+1..$]);
	return ret;
}
@safe unittest
{
	assert(_isAllUniq([["a", "b"], ["a", "c"], ["a", "d"]]));
	assert(!_isAllUniq([["a", "b"], ["a", "b"], ["a", "d"]]));
	assert(!_isAllUniq([["a", "b"], ["b", "a"], ["a", "d"]]));
}


private enum _isKeyAllUnique(Types...) = ()
{
	string[][] members;
	static foreach (Type; Types)
		members ~= [getKeyMemberNames!Type];
	return _isAllUniq(members);
}();

@safe unittest
{
	struct A { @key int a; @key int b;      int c; }
	struct B { @key int a;      int b; @key int c; }
	struct C {      int a; @key int b; @key int c; }
	struct D { @key int a; @key int b; @key int c; }
	static assert(_isKeyAllUnique!(A, B));
	static assert(_isKeyAllUnique!(A, C));
	static assert(!_isKeyAllUnique!(A, D));
}


/+
// キーの数が同じで、キーの名称が同じで、キーの型が同じならそのキー名を返す
private template getKeys(Types...)
{
	
	enum string[][] allKeyMembers = ()
	{
		string[][] ret;
		static foreach (T; Types)
			ret ~= [getKeyMemberNames!T];
		return ret;
	}();
	
	enum bool isSameNames(string[] rhs, string[] lhs) = rhs == lhs;
	
	template getKeyMemberTypes(size_t i, string[] keyMembers)
	{
		alias getMemberType(string member) = typeof(__traits(getMember, MemberTypes[i], member));
		alias getKeyMemberTypes = staticMap!(getMemberType, aliasSeqOf!keyMembers);
	}
	
	static if (allKeyMembers.length == 0)
	{
		// キーがない
		alias getKeys = AliasSeq!();
	}
	else static if (Filter!(ApplyLeft!(isSameNames, allKeyMembers[0]),aliasSeqOf!allKeyMembers).length
	                != allKeyMembers.length)
	{
		// キーの数や名称が違う
		alias getKeys = AliasSeq!();
	}
	else static if (
		!() {
			// すべてのキーの型が同じか判定する
			bool ret = true;
			alias firstKeyMemberTypes = getKeyMemberTypes!(0, allKeyMembers[0]);
			static foreach (i, keyMembers; allKeyMembers)
			{{
				alias keyMemberTypes = getKeyMemberTypes!(i, keyMembers);
				static foreach (j; 0..keyMemberTypes.length)
					ret &= is(keyMemberTypes[j] == firstKeyMemberTypes[j]);
			}}
			return ret;
		}())
	{
		// キーの型が違う
		alias getKeys = AliasSeq!();
	}
	else
	{
		// キーの数も名称も型もすべて同じ
		alias getKeys = aliasSeqOf!(allKeyMembers[0]);
	}
}

@system unittest
{
	struct A{ @key int a; int b; }
	struct B{ @key int a; int c; }
	struct C{ int a; @key int b; @key int c; }
	struct D{ int a; @key int b; @key int c; }
	static assert(getKeys!(A, B) == AliasSeq!("a"));
	static assert(getKeys!(A, C).length == 0);
	static assert(getKeys!(C, D) == AliasSeq!("b", "c"));
}
+/

private struct Kind
{
	string key;
	JSONValue value;
}

///
auto kind(T)(string name, T value)
{
	import bsky._internal.attr: v = value;
	return v(Kind(name, JSONValue(value)));
}

/// ditto
auto kind(T)(T value)
{
	import bsky._internal.attr: v = value;
	return v(Kind("kind", JSONValue(value)));
}

private alias _getKinds(T, string uk, alias tag) = aliasSeqOf!(()
{
	Kind[] ret;
	static if (hasValue!(T, Kind))
	{
		ret = [getValues!(T, Kind)];
	}
	else static if (getKeyMemberNames!T.length > 0)
	{
		static foreach (member; getKeyMemberNames!T)
		{
			static foreach (val; getValues!(__traits(getMember, T, member)))
			{
				static if (hasName!(__traits(getMember, T, member)))
					ret ~= Kind(getName!(__traits(getMember, T, member)), JSONValue(val));
				else
					ret ~= Kind(member, JSONValue(val));
			}
		}
	}
	else
	{
		// UDAがない場合、type, kind, tagをさがす
		static if (is(typeof(T.type) : string))
			ret ~= Kind("type", JSONValue(T.stringof));
		else static if (is(typeof(T.kind) : string))
			ret ~= Kind("kind", JSONValue(T.stringof));
		else static if (is(typeof(T.tag) : typeof(tag)))
			ret ~= Kind("tag", JSONValue(tag));
	}
	if (ret.length == 0)
		ret ~= Kind(uk, JSONValue(tag));
	return ret;
}());



private JSONValue _serializeToJsonImpl(Types...)(in SumType!Types dat)
{
	import std.sumtype: match;
	return dat.match!( (_) => _.serializeToJson() );
}

@system unittest
{
	alias MU = SumType!(int, string);
	MU dat = 10;
	auto mujson = _serializeToJsonImpl(dat);
	assert(mujson.type == JSONType.integer);
	assert(mujson.integer == 10);
	
	dat = "xxx";
	mujson = _serializeToJsonImpl(dat);
	assert(mujson.type == JSONType.string);
	assert(mujson.str == "xxx");
}

@system unittest
{
	struct A{ @key int a; int b; }
	struct B{ int a; @key int c; }
	
	SumType!(A, B) dat1 = A(1, 10);
	auto mujson1 = _serializeToJsonImpl(dat1);
	assert(mujson1.type == JSONType.object);
	assert(mujson1["a"].type == JSONType.integer);
	assert(mujson1["a"].integer == 1);
	assert(mujson1["b"].type == JSONType.integer);
	assert(mujson1["b"].integer == 10);
}

//
private JSONValue _serializeToJsonImpl(Types...)(in Tuple!Types dat) @trusted
{
	import std.meta: allSatisfy;
	enum bool isAvailableFieldName(string fieldName) = fieldName.length > 0;
	static if (allSatisfy!(isAvailableFieldName, Tuple!Types.fieldNames))
	{
		// すべてに名前がついている場合
		auto ret = JSONValue.emptyObject;
		static foreach (idx, memberName; Tuple!Types.fieldNames)
			ret.setValue(memberName, serializeToJson(dat[idx]));
		return ret;
	}
	else
	{
		// 名前のないフィールドがある場合は名前を無視して配列にしてしまう
		auto ret = JSONValue.emptyArray;
		static foreach (idx; 0..Tuple!Types.length)
			ret.array ~= serializeToJson(dat[idx]);
		return ret;
	}
}

@safe unittest
{
	auto dat1 = Tuple!(int, "test", string, "data")(10, "test");
	auto js1 = _serializeToJsonImpl(dat1);
	assert(js1.type == JSONType.object);
	assert("test" in js1);
	assert(js1["test"].type == JSONType.integer);
	assert(js1["test"].integer == 10);
	assert("data" in js1);
	assert(js1["data"].type == JSONType.string);
	assert(js1["data"].str == "test");
	
	auto dat2 = Tuple!(int, string)(10, "test");
	auto js2 = _serializeToJsonImpl(dat2);
	assert(js2.type == JSONType.array);
	assert((() @trusted => js2.array.length)() == 2);
	assert(js2[0].type == JSONType.integer);
	assert(js2[0].integer == 10);
	assert(js2[1].type == JSONType.string);
	assert(js2[1].str == "test");
}

/*******************************************************************************
 * serialize data to JSON
 */
JSONValue serializeToJson(T)(in T data)
{
	static if (isJSONizableRaw!T)
	{
		return data.json;
	}
	else static if (is(typeof(_serializeToJsonImpl(data)): JSONValue))
	{
		return _serializeToJsonImpl(data);
	}
	else static if (isArray!T)
	{
		JSONValue[] jvAry;
		auto len = data.length;
		jvAry.length = len;
		foreach (idx; 0..len)
			jvAry[idx] = serializeToJson(data[idx]);
		return JSONValue(jvAry);
	}
	else static if (isAssociativeArray!T)
	{
		JSONValue[string] jvObj;
		foreach (pair; data.byPair)
			jvObj[pair.key.to!string()] = serializeToJson(pair.value);
		return JSONValue(jvObj);
	}
	else
	{
		JSONValue ret;
		static foreach (memberIdx, member; T.tupleof)
		{{
			static if (!hasIgnore!member)
			{
				static if (hasIgnoreIf!member)
				{
					if (!getPredIgnoreIf!member(data))
					{
						static if (hasName!member)
						{
							enum fieldName = getName!member;
						}
						else
						{
							enum fieldName = __traits(identifier, member);
						}
						static if (hasConvBy!member)
						{
							ret[fieldName] = convTo!(member, JSONValue)(data.tupleof[memberIdx]);
						}
						else static if (isJSONizableRaw!(typeof(member)))
						{
							ret[fieldName] = data.tupleof[memberIdx].json;
						}
						else
						{
							ret[fieldName] = serializeToJson(data.tupleof[memberIdx]);
						}
					}
				}
				else
				{
					static if (hasName!member)
					{
						enum fieldName = getName!member;
					}
					else
					{
						enum fieldName = __traits(identifier, member);
					}
					static if (hasConvBy!member)
					{
						ret[fieldName] = convTo!(member, JSONValue)(data.tupleof[memberIdx]);
					}
					else static if (isJSONizableRaw!(typeof(member)))
					{
						ret[fieldName] = data.tupleof[memberIdx].json;
					}
					else
					{
						ret[fieldName] = serializeToJson(data.tupleof[memberIdx]);
					}
				}
			}
		}}
		return ret;
	}
}

/// ditto
string serializeToJsonString(T)(in T data, JSONOptions options = JSONOptions.none)
{
	return serializeToJson(data).toPrettyString(options);
}

/// ditto
void serializeToJsonFile(T)(in T data, string jsonfile, JSONOptions options = JSONOptions.none)
{
	import std.file, std.encoding;
	auto contents = serializeToJsonString(data, options);
	std.file.write(jsonfile, contents);
}

//
private void _deserializeFromJsonImpl(Types...)(ref SumType!Types dat, in JSONValue json)
{
	import std.sumtype: canMatch, match;
	alias MU = SumType!Types;
	final switch (json.type)
	{
	case JSONType.null_:
		() @trusted { dat = MU.init; }();
		break;
	case JSONType.string:
		static if (canMatch!(MU, string))
			() @trusted { dat = json.str; }();
		break;
	case JSONType.integer:
		static if (canMatch!(MU, long))
			() @trusted { dat = json.integer; }();
		else static if (canMatch!(MU, int))
			() @trusted { dat = json.integer; }();
		else static if (canMatch!(MU, short))
			() @trusted { dat = json.integer; }();
		else static if (canMatch!(MU, byte))
			() @trusted { dat = json.integer; }();
		break;
	case JSONType.uinteger:
		static if (canMatch!(MU, ulong))
			() @trusted { dat = json.uinteger; }();
		else static if (canMatch!(MU, uint))
			() @trusted { dat = json.uinteger; }();
		else static if (canMatch!(MU, ushort))
			() @trusted { dat = json.uinteger; }();
		else static if (canMatch!(MU, ubyte))
			() @trusted { dat = json.uinteger; }();
		break;
	case JSONType.float_:
		static if (canMatch!(MU, real))
			() @trusted { dat = json.floating; }();
		else static if (canMatch!(MU, double))
			() @trusted { dat = json.floating; }();
		else static if (canMatch!(MU, float))
			() @trusted { dat = json.floating; }();
		break;
	case JSONType.array:
		// 配列型の候補を選択
		alias AryTypes = Filter!(isArray, MU.Types);
		static if (AryTypes.length == 0)
		{
			// 配列型がないなら無視
			return;
		}
		else static if (AryTypes.length == 1)
		{
			// 配列型が1つならそれを最優先で選択
			() @trusted { dat = deserializeFromJson!(AryTypes[0])(tmp, json); }();
			return;
		}
		else
		{
			// 配列型が複数ある場合は1つ目のデータの要素で決定
			if (json.array.length == 0)
				() @trusted { dat = MU.init; }();
			import std.meta;
			alias ElementTypes = staticMap!(ForeachType, AryTypes);
			SumType!ElementTypes datElm;
			datElm.deserializeFromJson(json.array[0]);
			import std.sumtype: match;
			datElm.match!(
				(_){
					alias AryType = MU.Types[staticIndexOf!(typeof(_), ElementTypes)];
					() @trusted { dat = json.deserializeFromJson!AryType(); }();
				}
			);
			return;
		}
		assert(0);
	case JSONType.object:
		// オブジェクト型の候補を選択
		enum bool isObjType(T) = isAggregateType!T || isAssociativeArray!T;
		alias ObjTypes = Filter!(isObjType, Types);
		static if (ObjTypes.length == 0)
		{
			// オブジェクト型がないなら無視
		}
		else static if (ObjTypes.length == 1)
		{
			// オブジェクト型が1つならそれを最優先で選択
			() @trusted { dst = deserializeFromJson!(ObjTypes[0])(json); }();
		}
		else
		{
			// キーメンバーがすべて違う場合は、キーメンバーを持っている型を使用する
			static if (_isKeyAllUnique!ObjTypes)
			{
				static foreach (ObjType; ObjTypes)
				{{
					bool matchKeys = true;
					static foreach (memberName; getKeyMemberNames!ObjType)
						matchKeys &= cast(bool)(memberName in json);
					if (matchKeys)
					{
						() @trusted { dat = deserializeFromJson!ObjType(json); }();
						return;
					}
				}}
			}
			else
			{
				// オブジェクト型が複数ある場合はキーデータの要素で決定
				static foreach (idx; 0..ObjTypes.length)
				{
					// キーメンバーをすべて持っている型を探す
					static foreach (kind; _getKinds!(ObjTypes[idx], uniqueKey!(MU, "_tag"), staticIndexOf!(ObjTypes[idx], MU.Types)))
					{
						if (auto v = kind.key in json)
						{
							if (*v == kind.value)
							{
								() @trusted { dat = deserializeFromJson!(ObjTypes[idx])(json); }();
								return;
							}
						}
					}
				}
			}
		}
		break;
	case JSONType.true_:
	case JSONType.false_:
		static if (anySatisfy!(isBoolean, Types))
			() @trusted { dat = src.boolean; }();
		break;
	}
}
//
@system unittest
{
	struct A{ @key @value!1 int a; int b; }
	struct B{ @key @value!2 int a; int c; }
	struct C{ int a; @key @value!1 int b; @key @value!1 int c; }
	struct D{ int a; int b; @key int c; }
	import std.sumtype: match;
	SumType!(A, B) dat1;
	auto mujson1 = JSONValue(["a": JSONValue(1), "b": JSONValue(10)]);
	_deserializeFromJsonImpl(dat1, mujson1);
	auto result = dat1.match!(
		(A a) => 1,
		(B b) => 2,
	);
	assert(result == 1);
	
	SumType!(A[], B[]) dat2;
	auto mujson2 = JSONValue([JSONValue(["a": 1]), JSONValue(["b": 10])]);
	_deserializeFromJsonImpl(dat2, mujson2);
	result = dat2.match!(
		(A[] a) => 1,
		(B[] b) => 2,
	);
	assert(result == 1);
	
	SumType!(A, D) dat3;
	auto mujson3 = JSONValue(["c": 10]);
	_deserializeFromJsonImpl(dat3, mujson3);
	result = dat3.match!(
		(A a) => 1,
		(D b) => 2,
	);
	assert(result == 2);
}


private void _deserializeFromJsonImpl(Types...)(ref Tuple!Types dst, in JSONValue src) @trusted
{
	import std.meta: allSatisfy;
	enum bool isAvailableFieldName(string fieldName) = fieldName.length > 0;
	static if (allSatisfy!(isAvailableFieldName, Tuple!Types.fieldNames))
	{
		// すべてに名前がついている場合
		static foreach (idx, memberName; Tuple!Types.fieldNames)
			dst[idx].deserializeFromJson(src.getValue!JSONValue(memberName));
	}
	else
	{
		// 名前のないフィールドがある場合は名前を無視して配列にしてしまう
		if (src.type == JSONType.array && src.array.length == Tuple!Types.Types.length)
			static foreach (idx, Type; Tuple!Types.Types)
				dst[idx].deserializeFromJson(src[idx]);
	}
}

@safe unittest
{
	Tuple!(int, "test", string, "data") dat1;
	auto js1 = JSONValue(["test": JSONValue(10), "data": JSONValue("test")]);
	dat1._deserializeFromJsonImpl(js1);
	assert(dat1.test == 10);
	assert(dat1.data == "test");
	
	Tuple!(int, string) dat2;
	auto js2 = JSONValue([JSONValue(10), JSONValue("test")]);
	dat2._deserializeFromJsonImpl(js2);
	assert(dat2[0] == 10);
	assert(dat2[1] == "test");
}

/*******************************************************************************
 * deserialize data from JSON
 */
void deserializeFromJson(T)(ref T data, in JSONValue json)
{
	static if (isJSONizableRaw!T)
	{
		cast(void)fromJson(json, data);
	}
	else static if (__traits(compiles, _deserializeFromJsonImpl(data, json)))
	{
		_deserializeFromJsonImpl(data, json);
	}
	else static if (isArray!T)
	{
		if (json.type != JSONType.array)
			return;
		auto jvAry = (() @trusted => json.array)();
		static if (isDynamicArray!T)
			data.length = jvAry.length;
		foreach (idx, ref dataElm; data)
			deserializeFromJson(dataElm, jvAry[idx]);
	}
	else static if (isAssociativeArray!T)
	{
		if (json.type != JSONType.object)
			return;
		data.clear();
		alias KeyType = typeof(data.byKey.front);
		alias ValueType = typeof(data.byValue.front);
		foreach (pair; (() @trusted => json.object)().byPair)
		{
			import std.algorithm: move;
			data.update(pair.key.to!KeyType(),
			{
				ValueType ret;
				deserializeFromJson(ret, pair.value);
				return ret.move();
			}, (ref ValueType ret)
			{
				deserializeFromJson(ret, pair.value);
				return ret;
			});
		}
	}
	else
	{
		static foreach (memberIdx, member; T.tupleof)
		{{
			static if (!hasIgnore!member)
			{
				static if (hasName!member)
				{
					enum fieldName = getName!member;
				}
				else
				{
					enum fieldName = __traits(identifier, member);
				}
				static if (hasConvBy!member)
				{
					static if (hasEssential!member)
					{
						data.tupleof[memberIdx] = convFrom!(member, JSONValue)(json[fieldName]);
					}
					else
					{
						if (auto pJsonValue = fieldName in json)
						{
							try
								data.tupleof[memberIdx] = convFrom!(member, JSONValue)(*pJsonValue);
							catch (Exception e)
							{
								/* ignore */
							}
						}
						
					}
				}
				else static if (isJSONizableRaw!(typeof(member)))
				{
					static if (hasEssential!member)
					{
						cast(void)fromJson(json[fieldName], data.tupleof[memberIdx]);
					}
					else
					{
						import std.algorithm: move;
						auto tmp = json.getValue(fieldName, data.tupleof[memberIdx]);
						move(tmp, data.tupleof[memberIdx]);
					}
				}
				else
				{
					static if (hasEssential!member)
					{
						deserializeFromJson(data.tupleof[memberIdx], json[fieldName]);
					}
					else
					{
						if (auto pJsonValue = fieldName in json)
							deserializeFromJson(data.tupleof[memberIdx], *pJsonValue);
					}
				}
			}
		}}
	}
}

/// ditto
T deserializeFromJson(T)(in JSONValue jv)
{
	T ret;
	ret.deserializeFromJson(jv);
	return ret;
}

/// ditto
void deserializeFromJsonString(T)(ref T data, string jsonContents)
{
	deserializeFromJson(data, parseJSON(jsonContents));
}

/// ditto
T deserializeFromJsonString(T)(string jsonContents)
{
	T ret;
	ret.deserializeFromJsonString(jsonContents);
	return ret;
}

/// ditto
void deserializeFromJsonFile(T)(ref T data, string jsonFile)
{
	import std.file;
	deserializeFromJsonString(data, std.file.readText(jsonFile));
}

/// ditto
T deserializeFromJsonFile(T)(string jsonFile)
{
	T ret;
	ret.deserializeFromJsonFile(jsonFile);
	return ret;
}

@system unittest
{
	enum EnumVal
	{
		val1,
		val2
	}
	struct Data
	{
		EnumVal val;
	}
	Data data1 = Data(EnumVal.val1), data2 = Data(EnumVal.val2);
	auto jv = data1.serializeToJson();
	data2.deserializeFromJson(jv);
	assert(data1.val == data2.val);
}


@system unittest
{
	struct Data
	{
		string[uint] map;
	}
	Data data1 = Data([1: "1"]);
	Data data2 = Data([2: "2"]);
	auto jv = data1.serializeToJson();
	data2.deserializeFromJson(jv);
	assert(1 in data1.map);
	assert(1 in data2.map);
	assert(2 !in data2.map);
	assert(data2.map[1] == "1");
}

@system unittest
{
	static struct Data
	{
		string data1;
		@ignoreIf!(dat => dat.data2.length == 0)
		string data2;
	}
	Data data1 = Data("aaa", null);
	auto jv = data1.serializeToJson();
	assert("data2" !in jv);
}



///
JSONValue deepCopy(in JSONValue v) @property
{
	final switch (v.type)
	{
	case JSONType.null_:
	case JSONType.string:
	case JSONType.integer:
	case JSONType.uinteger:
	case JSONType.float_:
	case JSONType.true_:
	case JSONType.false_:
		return v;
	case JSONType.object:
		JSONValue[string] ret;
		foreach (key, val; v.object)
			ret[key] = deepCopy(val);
		return JSONValue(ret);
	case JSONType.array:
		auto ret = appender!(JSONValue[]);
		foreach (e; v.array)
			ret ~= deepCopy(e);
		return JSONValue(ret.data);
	}
}

@system unittest
{
	auto jv1 = JSONValue(["a": "A"]);
	auto jv2 = jv1;
	auto jv3 = jv1.deepCopy();
	jv1["a"] = "XXX";
	assert(jv1["a"].str == "XXX");
	assert(jv2["a"].str == "XXX");
	assert(jv3["a"].str == "A");
}
@system unittest
{
	auto jv1 = JSONValue(["a": ["A", "B", "C"]]);
	auto jv2 = jv1;
	auto jv3 = jv1.deepCopy();
	jv1["a"][0] = "XXX";
	assert(jv1["a"][0].str == "XXX");
	assert(jv2["a"][0].str == "XXX");
	assert(jv3["a"][0].str == "A");
}

/*******************************************************************************
 * JWT
 */
struct JWTValue
{
private:
	import std.digest.hmac;
	import std.digest.sha;
	import std.exception: enforce;
	import std.string: representation;
	immutable(ubyte)[] _key;
	JSONValue _payload;
public:
	/***************************************************************************
	 * 
	 */
	string type;
	
	/***************************************************************************
	 * 
	 */
	enum Algorithm
	{
		HS256, HS384, HS512
	}
	/// ditto
	Algorithm algorithm = Algorithm.HS256;
	
	
	/***************************************************************************
	 * 
	 */
	this(const(char)[] jwt, const(ubyte)[] key)
	{
		import std.base64;
		alias B64 = Base64URLNoPadding;
		auto jwtElms = split(jwt, '.');
		enforce(jwtElms.length == 3, "Unknown format");
		auto header = parseJSON(cast(const(char)[])B64.decode(jwtElms[0]));
		type = enforce(header.getValue("typ", string.init), "Unknown format");
		switch (header.getValue("alg", string.init))
		{
		case "HS256":
			algorithm = Algorithm.HS256;
			break;
		case "HS384":
			algorithm = Algorithm.HS384;
			break;
		case "HS512":
			algorithm = Algorithm.HS512;
			break;
		default:
			enforce(false, "Unsupported algorithm");
		}
		
		static immutable verrmsg = "JWT verification is failed";
		final switch (algorithm)
		{
		case Algorithm.HS256:
			enforce(B64.encode((jwtElms[0] ~ "." ~ jwtElms[1]).representation.hmac!SHA256(key)) == jwtElms[2], verrmsg);
			break;
		case Algorithm.HS384:
			enforce(B64.encode((jwtElms[0] ~ "." ~ jwtElms[1]).representation.hmac!SHA384(key)) == jwtElms[2], verrmsg);
			break;
		case Algorithm.HS512:
			enforce(B64.encode((jwtElms[0] ~ "." ~ jwtElms[1]).representation.hmac!SHA512(key)) == jwtElms[2], verrmsg);
			break;
		}
		
		_key = key.idup;
		_payload = parseJSON(cast(const(char)[])B64.decode(jwtElms[1]));
	}
	
	/// ditto
	this(const(char)[] jwt, const(char)[] key)
	{
		this(jwt, key.representation);
	}
	
	/// ditto
	this(const(char)[] typ, Algorithm algo, const(ubyte)[] key, JSONValue payload) @safe
	{
		type = typ.idup;
		algorithm = algo;
		_key = key.idup;
		_payload = payload;
	}
	
	/// ditto
	this(const(char)[] typ, Algorithm algo, const(char)[] key, JSONValue payload) @safe
	{
		this(typ, algo, key.representation, payload);
	}
	
	/// ditto
	this(const(char)[] typ, Algorithm algo, const(ubyte)[] key, JSONValue[string] payload) @safe
	{
		this(typ, algo, key, JSONValue(payload));
	}
	
	/// ditto
	this(const(char)[] typ, Algorithm algo, const(char)[] key, JSONValue[string] payload) @safe
	{
		this(typ, algo, key.representation, payload);
	}
	
	/// ditto
	this(const(char)[] typ, Algorithm algo, const(ubyte)[] key) @safe
	{
		this(typ, algo, key, JSONValue.init);
	}
	
	/// ditto
	this(const(char)[] typ, Algorithm algo, const(char)[] key) @safe
	{
		this(typ, algo, key.representation);
	}
	
	/// ditto
	this(Algorithm algo, const(ubyte)[] key, JSONValue payload) @safe
	{
		this("JWT", algo, key, payload);
	}
	
	/// ditto
	this(Algorithm algo, const(char)[] key, JSONValue payload) @safe
	{
		this(algo, key.representation, payload);
	}
	
	/// ditto
	this(Algorithm algo, const(ubyte)[] key, JSONValue[string] payload) @safe
	{
		this(algo, key, JSONValue(payload));
	}
	
	/// ditto
	this(Algorithm algo, const(char)[] key, JSONValue[string] payload) @safe
	{
		this(algo, key.representation, payload);
	}
	
	/// ditto
	this(Algorithm algo, const(ubyte)[] key) @safe
	{
		this("JWT", algo, key);
	}
	
	/// ditto
	this(Algorithm algo, const(char)[] key) @safe
	{
		this(algo, key.representation);
	}
	
	
	/***************************************************************************
	 * 
	 */
	void key(string key)
	{
		_key = key.representation;
	}
	/// dittp
	void key(const(ubyte)[] key)
	{
		_key = key.idup;
	}
	
	/***************************************************************************
	 * 
	 */
	ref inout(JSONValue) opIndex(string name) return inout
	{
		return _payload[name];
	}
	
	/***************************************************************************
	 * 
	 */
	void opIndexAssign(T)(auto ref T value, string name) return
	{
		_payload[name] = value;
	}
	
	/***************************************************************************
	 * 
	 */
	ref inout(JSONValue) payload() return inout
	{
		return _payload;
	}
	
	/***************************************************************************
	 * 
	 */
	string toString() const
	{
		string ret;
		import std.conv: text;
		import std.base64;
		alias B64 = Base64Impl!('+', '/', Base64.NoPadding);
		
		ret ~= B64.encode(text(`{"alg":"`, algorithm, `","typ":"`, type, `"}`).representation);
		ret ~= ".";
		ret ~= B64.encode(_payload.toString().representation);
		
		final switch (algorithm)
		{
		case Algorithm.HS256:
			return ret ~ "." ~ cast(string)B64.encode(ret.representation.hmac!SHA256(_key));
		case Algorithm.HS384:
			return ret ~ "." ~ cast(string)B64.encode(ret.representation.hmac!SHA384(_key));
		case Algorithm.HS512:
			return ret ~ "." ~ cast(string)B64.encode(ret.representation.hmac!SHA512(_key));
		}
	}
}

/// ditto
@system unittest
{
	import std.exception;
	static immutable testjwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
		~".eyJ0ZXN0a2V5IjoidGVzdHZhbHVlIn0"
		~".AXHSKa2ubvg6jMckkYaWgCXluhOamfFDk8y163X4DPs";
	
	auto jwt = JWTValue(JWTValue.Algorithm.HS256, "testsecret");
	jwt["testkey"] = "testvalue";
	assert(jwt.toString() == testjwt);
	
	auto jwt2 = JWTValue(testjwt, "testsecret");
	assert(jwt2["testkey"].str == "testvalue");
	assert(jwt2.toString() == jwt.toString());
	
	assertThrown(JWTValue(testjwt, "testsecret2"));
}

/*******************************************************************************
 * 
 */
void setValue(T)(ref JWTValue dat, string name, T val)
{
	dat._payload.setValue(name, val);
}

/*******************************************************************************
 * 
 */
T getValue(T)(in JWTValue dat, string name, lazy T defaultVal)
{
	return dat._payload.getValue(name, defaultVal);
}

@safe unittest
{
	auto jwt = JWTValue(JWTValue.Algorithm.HS256, "test");
	assert(jwt.type == "JWT");
	jwt = JWTValue("Test", JWTValue.Algorithm.HS256, "test", ["test": JSONValue("test")]);
	assert(jwt.type == "Test");
	assert(jwt.getValue("test", "x") == "test");
	jwt = JWTValue(JWTValue.Algorithm.HS256, "test", ["test": JSONValue("test")]);
	assert(jwt.type == "JWT");
	assert(jwt.getValue("test", "x") == "test");
	jwt = JWTValue(JWTValue.Algorithm.HS256, "test", JSONValue(["test": "test"]));
	assert(jwt.type == "JWT");
	assert(jwt.getValue("test", "x") == "test");
	jwt = JWTValue("Test", JWTValue.Algorithm.HS256, "test", JSONValue(["test": "test"]));
	assert(jwt.type == "Test");
	assert(jwt.getValue("test", "x") == "test");
	jwt = JWTValue("Test", JWTValue.Algorithm.HS256, "test");
	assert(jwt.type == "Test");
	assert(jwt.getValue("test", "x") == "x");
}


/*******************************************************************************
 * シリアライズ/デシリアライズ
 */
JWTValue serializeToJwt(T)(in T data, JWTValue.Algorithm algo, const(ubyte)[] key)
{
	auto ret = JWTValue(algo, key);
	ret._payload = serializeToJson(data);
	return ret;
}

/// ditto
JWTValue serializeToJwt(T)(in T data, JWTValue.Algorithm algo, const(char)[] key)
{
	import std.string: representation;
	return serializeToJwt(data, algo, key.representation);
}

/// ditto
JWTValue serializeToJwt(T)(in T data, const(ubyte)[] key)
{
	return serializeToJwt(data, JWTValue.Algorithm.HS256, key);
}

/// ditto
JWTValue serializeToJwt(T)(in T data, const(char)[] key)
{
	import std.string: representation;
	return serializeToJwt(data, key.representation);
}

/// ditto
string serializeToJwtString(T)(in T data, JWTValue.Algorithm algo, const(ubyte)[] key)
{
	return serializeToJwt(data, algo, key).toString();
}

/// ditto
string serializeToJwtString(T)(in T data, JWTValue.Algorithm algo, const(char)[] key)
{
	import std.string: representation;
	return serializeToJwtString(data, algo, key.representation);
}

/// ditto
string serializeToJwtString(T)(in T data, const(ubyte)[] key)
{
	return serializeToJwtString(data, JWTValue.Algorithm.HS256, key);
}

/// ditto
string serializeToJwtString(T)(in T data, const(char)[] key)
{
	import std.string: representation;
	return serializeToJwtString(data, key.representation);
}

/// ditto
void deserializeFromJwt(T)(ref T data, JWTValue jwt)
{
	deserializeFromJson(data, jwt._payload);
}

/// ditto
void deserializeFromJwtString(T)(ref T data, const(char)[] jwt, const(char)[] key)
{
	deserializeFromJson(data, JWTValue(jwt, key)._payload);
}


/// ditto
@system unittest
{
	import std.exception;
	static immutable testjwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
		~".eyJ0ZXN0a2V5IjoidGVzdHZhbHVlIn0"
		~".AXHSKa2ubvg6jMckkYaWgCXluhOamfFDk8y163X4DPs";
	
	struct Dat { string testkey; }
	auto dat = Dat("testvalue");
	
	auto jwt1 = serializeToJwt(dat, JWTValue.Algorithm.HS256, "testsecret");
	assert(jwt1.toString() == testjwt);
	auto jwt2 = serializeToJwt(dat, "testsecret");
	assert(jwt2.toString() == testjwt);
	assert(serializeToJwtString(dat, JWTValue.Algorithm.HS256, "testsecret") == testjwt);
	assert(serializeToJwtString(dat, "testsecret") == testjwt);
	
	Dat dat2;
	dat2.deserializeFromJwt(jwt1);
	assert(dat2 == dat);
	
	Dat dat3;
	dat3.deserializeFromJwtString(testjwt, "testsecret");
	assert(dat3 == dat);
}
