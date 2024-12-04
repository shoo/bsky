module src.storage;

import std.datetime;

/*******************************************************************************
 * Summary of user data
 */
struct UserData
{
	///
	string did;
	///
	string handle;
	///
	string displayName;
	///
	SysTime modified;
}

/*******************************************************************************
 * Summary of post data
 */
struct PostData
{
	///
	string did;
	///
	string handle;
	///
	string displayName;
	///
	string uri;
	///
	string url;
	///
	size_t replyCount;
	///
	size_t likeCount;
	///
	size_t repostCount;
	///
	size_t quoteCount;
	///
	UserData[] likedBy;
	///
	UserData[] repostedBy;
	///
	UserData[] quotedBy;
	///
	string text;
	///
	string[] imageUrls;
	///
	SysTime postAt;
}

/*******************************************************************************
 * 
 */
struct CacheData
{
private:
	import core.sync.mutex;
	import std.json;
	
	string _cacheFile = "cache.json";
	JSONValue[string][string] _cache;
	Mutex _mutex;
	
	static JSONValue _toJSONValue(ref UserData ud) @safe
	{
		return JSONValue([
			"did": ud.did,
			"handle": ud.handle,
			"displayName": ud.displayName,
			"modified": ud.modified.toISOExtString()]);
	}
	static JSONValue _toJSONValue(ref UserData[] udAry) @trusted
	{
		auto jv = JSONValue.emptyArray;
		foreach (d; udAry)
			jv.array ~= _toJSONValue(d);
		return jv;
	}
	static JSONValue _toJSONValue(ref PostData pd) @safe
	{
		return JSONValue([
			"uri": JSONValue(pd.uri),
			"did": JSONValue(pd.did),
			"handle": JSONValue(pd.handle),
			"displayName": JSONValue(pd.displayName),
			"replyCount": JSONValue(pd.replyCount),
			"likeCount": JSONValue(pd.likeCount),
			"repostCount": JSONValue(pd.repostCount),
			"quoteCount": JSONValue(pd.quoteCount),
			"likedBy": _toJSONValue(pd.likedBy),
			"repostedBy": _toJSONValue(pd.repostedBy),
			"quotedBy": _toJSONValue(pd.quotedBy),
			"text": JSONValue(pd.text),
			"imageUrls": JSONValue(pd.imageUrls),
			"postAt": JSONValue(pd.postAt.toISOExtString()),
			]);
	}
	static UserData _getUserDataFromJSON(ref JSONValue jv) @safe
	{
		return UserData(
			did: jv["did"].str,
			handle: jv["handle"].str,
			displayName: jv["displayName"].str,
			modified: SysTime.fromISOExtString(jv["modified"].str));
	}
	static UserData[] _getUserDataListFromJSON(ref JSONValue jv) @trusted
	{
		UserData[] ret;
		foreach (ref d; jv.array)
			ret ~= _getUserDataFromJSON(d);
		return ret;
	}
	static PostData _getPostDataFromJSON(ref JSONValue jv) @safe
	{
		return PostData(
			uri: jv["uri"].str,
			replyCount: jv["replyCount"].get!size_t,
			likeCount: jv["likeCount"].get!size_t,
			repostCount: jv["repostCount"].get!size_t,
			quoteCount: jv["quoteCount"].get!size_t,
			likedBy: _getUserDataListFromJSON(jv["likedBy"]),
			repostedBy: _getUserDataListFromJSON(jv["repostedBy"]),
			quotedBy: _getUserDataListFromJSON(jv["quotedBy"]));
	}
public:
	///
	void initialize(ref string[] args) @trusted
	{
		import std.getopt, std.file;
		_mutex = new Mutex;
		bool force;
		args.getopt(std.getopt.config.passThrough,
			"cache", &_cacheFile,
			"force|f", &force);
		if (!force && _cacheFile.exists)
		{
			auto jv = parseJSON(_cacheFile.readText());
			foreach (ref record; jv.array)
				set(record["type"].str, record["key"].str, record["value"]);
		}
	}
	
	///
	void save() @trusted
	{
		if (_cacheFile.length == 0)
			return;
		auto jv = JSONValue.emptyArray;
		synchronized (_mutex) foreach (type, ref typeData; _cache)
		{
			foreach (key, ref record; typeData)
			{
				jv.array ~= JSONValue([
					"type":  JSONValue(type),
					"key":   JSONValue(key),
					"value": record,
				]);
			}
		}
		import std.file;
		std.file.write(_cacheFile, jv.toString(JSONOptions.doNotEscapeSlashes));
	}
	
	///
	bool get(T = JSONValue)(string type, string key, ref T dst) const @trusted
	{
		if (auto jvRepo = type in _cache)
		{
			if (auto rec = key in *jvRepo)
			{
				dst = *rec;
				return true;
			}
		}
		return false;
	}
	///
	bool get(T: UserData)(string type, string key, ref T dst) const @safe
	{
		JSONValue jv;
		if (get!JSONValue(type, key, jv))
		{
			dst = _getUserDataFromJSON(jv);
			return true;
		}
		return false;
	}
	///
	bool get(T: UserData[])(string type, string key, ref T dst) const @safe
	{
		JSONValue jv;
		if (get!JSONValue(type, key, jv))
		{
			dst = _getUserDataListFromJSON(jv);
			return true;
		}
		return false;
	}
	///
	bool get(T: PostData)(string type, string key, ref T dst) const @safe
	{
		JSONValue jv;
		if (get!JSONValue(type, key, jv))
		{
			dst = _getPostDataFromJSON(jv);
			return true;
		}
		return false;
	}
	
	///
	void set(T = JSONValue)(string type, string key, T value) @safe
	{
		_cache.update(type,
			() => [key: value],
			(ref JSONValue[string] col)
		{
			col.update(key,
				() => value,
				(ref JSONValue rec)
			{
				rec = value;
				return rec;
			});
			return col;
		});
	}
	/// ditto
	void set(T: UserData)(string type, string key, T value) @safe
	{
		set(type, key, _toJSONValue(value));
	}
	/// ditto
	void set(T: UserData[])(string type, string key, T value) @safe
	{
		set(type, key, _toJSONValue(value));
	}
	/// ditto
	void set(T: PostData)(string type, string key, T value) @safe
	{
		set(type, key, _toJSONValue(value));
	}
	
	/// ditto
	bool getShared(T)(string type, string key, ref T value) shared const @trusted
	{
		synchronized (_mutex)
			return (cast()this).get(type, key, value);
	}
	
	/// ditto
	void setShared(T)(string type, string key, T value) shared @trusted
	{
		synchronized (_mutex)
			(cast()this).set(type, key, value);
	}
}

@safe unittest
{
	import std.json;
	CacheData cache;
	cache.set("test", "testCollection", JSONValue("testValue"));
	JSONValue jv;
	cache.get("test", "testCollection", jv);
	cache._cacheFile = "test.json";
	assert(jv.str == "testValue");
	cache.save();
}
