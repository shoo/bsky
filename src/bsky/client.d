/*******************************************************************************
 * Bluesky client
 * 
 * License: BSL-1.0
 */
module bsky.client;

import std.array;
import std.json;
import std.exception;
import std.sumtype;
import std.string;
import bsky.user;
import bsky.auth;
import bsky.post;
import bsky.data;
import bsky._internal;

/*******************************************************************************
 * 
 */
static struct FetchRange(T)
{
private:
	string delegate(JSONValue jv) @safe _getCursor;
	JSONValue[] delegate(JSONValue jv) @safe _getElements;
	JSONValue delegate(string[string] param) @safe _httpGet;
	JSONValue[] _fetchedElements;
	string _cursor;
	string[string] _params;
	void _fetch() @safe
	{
		if (_cursor.length > 0)
			_params["cursor"] = _cursor;
		auto res = _httpGet(_params);
		_fetchedElements = _getElements(res);
		if (_fetchedElements.length == 0)
		{
			_cursor = null;
			return;
		}
		auto newCursor = _getCursor(res);
		if (newCursor.length == 0 || (newCursor.length > 0 && newCursor == _cursor))
		{
			_cursor = null;
			return;
		}
		_cursor = newCursor;
	}
public:
	/***************************************************************************
	 * 
	 */
	bool empty() const @safe
	{
		return _fetchedElements.length == 0 && _cursor.length == 0;
	}
	/***************************************************************************
	 * 
	 */
	T front() const @trusted
	{
		T ret;
		ret.deserializeFromJson(_fetchedElements[0]);
		return ret;
	}
	/***************************************************************************
	 * 
	 */
	void popFront() @safe
	{
		_fetchedElements = _fetchedElements[1..$];
		if (_fetchedElements.length == 0 && _cursor.length > 0)
			_fetch();
	}
	/***************************************************************************
	 * 
	 */
	void setFetchLength(size_t len) @safe
	{
		import std.conv: to;
		_params["limit"] = len.to!string;
	}
}


private void _parseFacetImpl(alias getDid)(ref JSONValue dst, string text) @safe
{
	import std.regex;
	enum reFacet = ctRegex!(r"(?:^|(?<=\s|\())("
		~   r"@(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?"
		~ r")|("
		~   r"https?:\/\/(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}"
		~   r"\b(?:[-a-zA-Z0-9()@:%_\+.~#?&//=]*[-a-zA-Z0-9@%_\+~#//=])?"
		~ r")|("
		~   r"(?:^|(?<=\s))(?:#[^\d\s]\S*)(?:(?=\s)|$)"
		~ r")");
	foreach (m; text.matchAll(reFacet))
	{
		auto jv = JSONValue.emptyObject;
		jv.setValue("index", JSONValue([
			"byteStart": m.pre.length,
			"byteEnd": m.pre.length + m.hit.length]));
		if (m[1].length > 0)
			jv.setValue("features", JSONValue([JSONValue([
				"$type": "app.bsky.richtext.facet#mention",
				"did": getDid(m.hit)])]));
		if (m[2].length > 0)
			jv.setValue("features", JSONValue([JSONValue([
				"$type": "app.bsky.richtext.facet#link",
				"uri": m[2]])]));
		if (m[3].length > 0)
			jv.setValue("features", JSONValue([JSONValue([
				"$type": "app.bsky.richtext.facet#tag",
				"tag": m[3][1..$]])]));
		(() @trusted => dst.array ~= jv)();
	}
}
@system unittest
{
	alias getDid = (handle) @safe => "did:plc:test";
	auto jv = JSONValue.emptyArray;
	_parseFacetImpl!getDid(jv, "test");
	assert(jv.array.length == 0);
	jv = JSONValue.emptyArray;
	_parseFacetImpl!getDid(jv, "test https://dlang.org test");
	assert(jv.array.length == 1);
	assert(jv[0]["features"][0]["$type"].str == "app.bsky.richtext.facet#link");
	assert(jv[0]["features"][0]["uri"].str == "https://dlang.org");
	assert(jv[0]["index"]["byteStart"].uinteger == 5);
	assert(jv[0]["index"]["byteEnd"].uinteger == 22);
	jv = JSONValue.emptyArray;
	_parseFacetImpl!getDid(jv, "test https://dlang.org @test.bsky.social test #test test #end");
	assert(jv.array.length == 4);
	assert(jv[0]["features"][0]["$type"].str == "app.bsky.richtext.facet#link");
	assert(jv[0]["features"][0]["uri"].str == "https://dlang.org");
	assert(jv[0]["index"]["byteStart"].uinteger == 5);
	assert(jv[0]["index"]["byteEnd"].uinteger == 22);
	assert(jv[1]["features"][0]["$type"].str == "app.bsky.richtext.facet#mention");
	assert(jv[1]["features"][0]["did"].str == "did:plc:test");
	assert(jv[1]["index"]["byteStart"].uinteger == 23);
	assert(jv[1]["index"]["byteEnd"].uinteger == 40);
	assert(jv[2]["features"][0]["$type"].str == "app.bsky.richtext.facet#tag");
	assert(jv[2]["features"][0]["tag"].str == "test");
	assert(jv[2]["index"]["byteStart"].uinteger == 46);
	assert(jv[2]["index"]["byteEnd"].uinteger == 51);
	assert(jv[3]["features"][0]["$type"].str == "app.bsky.richtext.facet#tag");
	assert(jv[3]["features"][0]["tag"].str == "end");
	assert(jv[3]["index"]["byteStart"].uinteger == 57);
	assert(jv[3]["index"]["byteEnd"].uinteger == 61);
}

/*******************************************************************************
 * Bluesky client
 */
class Bluesky
{
private:
	import std.concurrency;
	import bsky.lexicons;
	import bsky._internal.httpc;
	import core.internal.gc.impl.conservative.gc;
public:
	///
	alias ReplyRef = app.bsky.feed.Post.ReplyRef;
	///
	alias PostRef = com.atproto.StrongRef;
	///
	alias Post = bsky.post.Post;
	
private:
	string _endpoint = "https://bsky.social";
	shared AtprotoAuth _auth;
	shared AutoUpdateStrategy _updateStrategy;
	Tid _tidUpdateTokens;
	HttpClientBase _httpClient;
	
	void _autoUpdateSession() shared @safe
	{
		import core.atomic;
		final switch (_updateStrategy.atomicLoad)
		{
		case AutoUpdateStrategy.none:
			break;
		case AutoUpdateStrategy.herf:
			_auth.updateSession(AtprotoAuth.UpdateStrategy.herf);
			break;
		case AutoUpdateStrategy.before5min:
			_auth.updateSession(AtprotoAuth.UpdateStrategy.before5min);
			break;
		case AutoUpdateStrategy.expired:
			_auth.updateSession(AtprotoAuth.UpdateStrategy.expired);
			break;
		}
	}
	void _autoUpdateSession() @trusted
	{
		(cast(shared)this)._autoUpdateSession();
	}
	
	string _getBearer() @safe
	{
		if (!_auth)
			return null;
		_autoUpdateSession();
		return _auth.bearer;
	}
	
	JSONValue _get(string path, string[string] param = null) @safe
	{
		return _httpClient.get(_endpoint ~ path, param, &_getBearer);
	}
	
	JSONValue _post(string path, immutable(ubyte)[] data, string mimeType) @safe
	{
		return _httpClient.post(_endpoint ~ path, data, mimeType, &_getBearer);
	}
	
	JSONValue _post(string path, JSONValue data) @safe
	{
		auto p = data is JSONValue.init ? (immutable(ubyte)[]).init : data.toJSON().representation;
		return _post(path, p, "application/json");
	}
	
	void _enforceHttpRes(JSONValue res) @trusted
	{
		if (_httpClient.getLastStatusCode() == 200)
			return;
		throw new BlueskyClientException(_httpClient.getLastStatusCode(), _httpClient.getLastStatusReason(),
			res.getValue("error", "Error"),
			res.getValue("message", "Unknown error occurred."),
			_httpClient.getLastStatusReason() ~ "\n\n"
			~ res.getValue("error", "Error") ~ ": "
			~ res.getValue("message", "Unknown error occurred."));
	}
	
	string _fetchSequencialData(
		string delegate(JSONValue jv) @safe getCursor,
		JSONValue[] delegate(JSONValue jv) @safe getElements,
		void delegate(JSONValue[] jv) @safe append,
		string path, string cursor, size_t len, string[string] params) @safe
	{
		import std.conv;
		import std.algorithm: min;
		
		size_t remain = len;
		auto query = params.dup;
		query["limit"] = min(remain + 10, 100).to!string;
		if (cursor !is null)
			query["cursor"] = cursor;
		string oldCursor = cursor;
		while (remain > 0)
		{
			auto res = _get(path, query);
			_enforceHttpRes(res);
			auto elements = getElements(res);
			if (elements.length == 0)
				break;
			auto newCursor = getCursor(res);
			auto fetchLen = min(remain, elements.length);
			if (newCursor.length == 0)
			{
				append(elements[0..fetchLen]);
				return null;
			}
			if (newCursor.length > 0 && newCursor == oldCursor)
			{
				append(elements[0..fetchLen]);
				return newCursor;
			}
			append(elements[0..fetchLen]);
			remain -= fetchLen;
			oldCursor = newCursor;
			query["cursor"] = newCursor;
			query["limit"] = len == size_t.max ? "100" : min(remain + 10, 100).to!string;
		}
		return oldCursor;
	}
	
	FetchRange!T _makeFetchRange(T)(
		string delegate(JSONValue jv) @safe getCursor,
		JSONValue[] delegate(JSONValue jv) @safe getElements,
		JSONValue delegate(string[string] param) @safe httpGet,
		string cursor, size_t limit, string[string] params) @safe
	{
		import std.conv: to;
		auto ret = FetchRange!T(getCursor, getElements, httpGet, null, cursor, params.dup);
		ret._params["limit"] = limit.to!string;
		ret._fetch();
		return ret;
	}
	FetchRange!T _makeFetchRange(T)(
		string delegate(JSONValue jv) @safe getCursor,
		JSONValue[] delegate(JSONValue jv) @safe getElements,
		string path, string cursor, size_t limit, string[string] params) @safe
	{
		import std.conv: to;
		JSONValue httpGet(string[string] param) @safe
		{
			auto res = _get(path, param);
			_enforceHttpRes(res);
			return res;
		}
		return _makeFetchRange!T(getCursor, getElements, &httpGet, cursor, limit, params);
	}
	
	void _parseFacet(ref JSONValue dst, string text) @safe
	{
		_parseFacetImpl!((h) @safe => resolveHandle(h))(dst, text);
	}
	
	/***************************************************************************
	 * 自動セッションアップデート
	 * 
	 * 以下を使用すると定期的にセッションのアクセストークン更新を行う
	 * しかしながら、開始と終了のタイミングをうまくコントロールするのが難しい
	 * ため使用を一旦保留。
	 */
	version (none)
	void _entryIntervalUpdateTokens() shared
	{
		import std.datetime;
		import core.atomic;
		SysTime tim = Clock.currTime;
		tim += 1.hours;
		bool running;
		while (running && !receiveTimeout(500.msecs,
			(bool cond) { running = false; },
			(Duration dur) { tim += dur; }))
		{
			if (tim < Clock.currTime)
			{
				_autoUpdateSession();
				tim += 1.hours;
			}
		}
	}
	
public:
	/***************************************************************************
	 * Constructor
	 */
	this(Client = CurlHttpClient!())(string endpoint, AtprotoAuth auth = null, Client client = new Client) @trusted
	{
		this(endpoint, cast(shared)auth, client);
	}
	/// ditto
	this(Client: HttpClientBase)(string endpoint, AtprotoAuth auth = null, Client client) @trusted
	{
		this(endpoint, cast(shared)auth, client);
	}
	/// ditto
	this(Client = CurlHttpClient!())(string endpoint, shared AtprotoAuth auth, Client client = new Client) @safe
	{
		this(endpoint, auth, cast(HttpClientBase)client);
	}
	/// ditto
	this(Client: HttpClientBase)(string endpoint, shared AtprotoAuth auth, Client client) @safe
	{
		_httpClient = client;
		_endpoint = endpoint;
		_auth = auth;
	}
	/// ditto
	this(Client = CurlHttpClient!())(AtprotoAuth auth, Client client = new Client) @trusted
	{
		this(cast(shared)auth, client);
	}
	/// ditto
	this(Client: HttpClientBase)(AtprotoAuth auth, Client client) @trusted
	{
		this(cast(shared)auth, client);
	}
	/// ditto
	this(Client = CurlHttpClient!())(shared AtprotoAuth auth, Client client = new Client) @safe
	{
		this(auth, cast(HttpClientBase)client);
	}
	/// ditto
	this(Client: HttpClientBase)(shared AtprotoAuth auth, Client client) @safe
	{
		this("https://bsky.social", auth, client);
	}
	/// ditto
	this(Client = CurlHttpClient!())(Client client = new Client) @safe
	{
		this(cast(HttpClientBase)client);
	}
	/// ditto
	this(Client: HttpClientBase)(Client client) @safe
	{
		this(AtprotoAuth.init, client);
	}
	
	
	/***************************************************************************
	 * Login
	 */
	void login(AtprotoAuth auth) @trusted
	{
		login(cast(shared)auth);
	}
	/// ditto
	void login(shared AtprotoAuth auth) @safe
	in (auth)
	{
		_auth = auth;
	}
	/// ditto
	void login(Client = CurlHttpClient!())(string id, string password, Client client = null) @safe
	{
		login(id, password, cast(HttpClientBase)client);
	}
	/// ditto
	void login(Client: HttpClientBase)(string id, string password, Client client) @safe
	{
		if (!_auth)
			login(new AtprotoAuth(_endpoint, client ? client : _httpClient));
		_auth.createSession(id, password);
	}
	
	/***************************************************************************
	 * Logout
	 */
	void logout() @safe
	{
		_auth.deleteSession();
	}
	
	// login/logout
	@safe unittest
	{
		scope client = _createDummyClient(null, null, null, null);
		client.httpc.addResult(_createDummySession("did:plc:2qfqobqz6dzrfa3jv74i6k6m", "dxutjikmg579.hfor.org").toJson);
		client.login("dxutjikmg579.hfor.org", "dummy", client.httpc);
		with (client.req)
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.server.createSession`);
			assert(query == ``);
			assert(bodyBinary == `{"identifier":"dxutjikmg579.hfor.org","password":"dummy"}`.representation);
		}
		assert(client.available);
		client.httpc.clearResult();
		client.httpc.addResult(JSONValue.init);
		client.logout();
		with (client.req)
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.server.deleteSession`);
			assert(query == ``);
			assert(bodyBinary == ``.representation);
		}
		assert(!client.available);
	}
	
	/***************************************************************************
	 * Account availability
	 */
	bool available() const @safe
	{
		return _auth ? _auth.available : false;
	}
	
	/***************************************************************************
	 * Auto update access token types
	 */
	enum AutoUpdateStrategy
	{
		/***********************************************************************
		 * 
		 */
		none,
		/***********************************************************************
		 * 
		 */
		herf,
		/***********************************************************************
		 * 
		 */
		before5min,
		/***********************************************************************
		 * 
		 */
		expired,
	}
	
	/***************************************************************************
	 * Auto update access tokens
	 */
	void autoUpdateAccessTokens(bool cond) @safe
	{
		autoUpdateAccessTokens(cond ? AutoUpdateStrategy.expired : AutoUpdateStrategy.none);
	}
	
	/// ditto
	void autoUpdateAccessTokens(AutoUpdateStrategy type) @safe
	{
		import core.atomic;
		_updateStrategy.atomicStore(type);
	}
	
	/// ditto
	AutoUpdateStrategy autoUpdateAccessTokens() const @safe
	{
		import core.atomic;
		return _updateStrategy.atomicLoad;
	}
	
	// autoUpdateAccessTokens
	@safe unittest
	{
		import std.datetime;
		scope client = _createDummyClient(null, null, null, null);
		auto sessionA = _createDummySession("did:plc:2qfqobqz6dzrfa3jv74i6k6m", "dxutjikmg579.hfor.org",
			expireAt: DateTime(2000, 1, 1, 0, 0, 0));
		client.httpc.addResult(sessionA.toJson);
		client.login("dxutjikmg579.hfor.org", "dummy", client.httpc);
		with (client.req)
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.server.createSession`);
			assert(query == ``);
			assert(bodyBinary == `{"identifier":"dxutjikmg579.hfor.org","password":"dummy"}`.representation);
		}
		assert(client.bsky._auth.storeSessionOnlyToken.accessJwt == sessionA.accessJwt);
		assert(client.bsky._auth.storeSessionOnlyToken.refreshJwt == sessionA.refreshJwt);
		client.httpc.clearResult();
		
		client.autoUpdateAccessTokens = true;
		assert(client.autoUpdateAccessTokens == AutoUpdateStrategy.expired);
		// 1. getSessionで400エラー(ExpiredToken)
		client.httpc.addResult(400, "ExpiredToken", JSONValue(["error": "ExpiredToken"]));
		// 2. refreshSessionで200
		auto sessionB = _createDummySession("did:plc:2qfqobqz6dzrfa3jv74i6k6m", "dxutjikmg579.hfor.org");
		assert(sessionA.accessJwt != sessionB.accessJwt);
		client.httpc.addResult(JSONValue([
			"accessJwt": sessionB.accessJwt,
			"refreshJwt": sessionB.refreshJwt,
			"handle": sessionB.handle,
			"did": sessionB.did]));
		// 3. getSessionで200
		client.httpc.addResult(sessionB.toJson);
		cast(void)client.bsky._getBearer();
		with (client.req(0))
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/com.atproto.server.getSession`);
			assert(query == ``);
		}
		with (client.req(1))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.server.refreshSession`);
			assert(query == ``);
		}
		with (client.req(2))
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/com.atproto.server.getSession`);
			assert(query == ``);
		}
		assert(client.bsky._auth.storeSessionOnlyToken.accessJwt == sessionB.accessJwt);
		assert(client.bsky._auth.storeSessionOnlyToken.refreshJwt == sessionB.refreshJwt);
	}
	
	
	/***************************************************************************
	 * Profile
	 * 
	 * - getProfile : Raw API execution.
	 * - profile : Get target profile.
	 * - getProfiles : Raw API execution.
	 * - fetchProfiles : Execute multiple APIs to get all data.
	 * - profiles : Range to perform API execution when needed.
	 * 
	 * Params:
	 *     name = did or handle, default is user of current session.
	 *     names = did or handle list
	 *     actors = did or handle list, max length is 25
	 */
	JSONValue getProfile(string name = null) @safe
	{
		return _get("/xrpc/app.bsky.actor.getProfile", ["actor": name is null ? _auth.did : name]);
	}
	/// ditto
	Profile profile(string name = null) @trusted
	{
		Profile ret;
		ret.deserializeFromJson(getProfile(name));
		return ret;
	}
	/// ditto
	JSONValue getProfiles(string[] actors) @trusted
	in (actors.length > 0 && actors.length <= 25)
	{
		import std.algorithm: map;
		import std.uri: encodeComponent;
		import std.conv: to;
		import std.format: format;
		auto encNames = actors.map!(name => name.encodeComponent()).array;
		auto path = format!"/xrpc/app.bsky.actor.getProfiles?%-(actors=%s&%)"(encNames);
		auto ret = _get(path, null);
		_enforceHttpRes(ret);
		return ret;
	}
	/// ditto
	Profile[] fetchProfiles(string[] names) @safe
	{
		import std.range;
		auto ret = new Profile[names.length];
		size_t pos = 0;
		foreach (chunkOfNames; names.chunks(25))
		{
			auto res = getProfiles(chunkOfNames);
			if (auto profs = "profiles" in res)
			{
				() @trusted {
					foreach (size_t i, ref p; *profs)
						ret[pos++].deserializeFromJson(p);
				} ();
			}
		}
		return ret[0..pos];
	}
	/// ditto
	FetchRange!Profile profiles(string[] names) @safe
	{
		import std.algorithm: min, map;
		import std.conv: to;
		import std.uri: encodeComponent;
		size_t cursorIdx;
		auto encNames = names.map!(name => name.encodeComponent()).array;
		JSONValue httpGet(string[string])
		{
			auto idx = cursorIdx;
			auto idxEnd = min(idx + 25, names.length);
			import std.format: format;
			auto path = format!"/xrpc/app.bsky.actor.getProfiles?%-(actors=%s&%)"(encNames[idx..idxEnd]);
			auto jv = _get(path, null);
			_enforceHttpRes(jv);
			cursorIdx = idxEnd;
			return jv;
		}
		return _makeFetchRange!Profile(
			jv => cursorIdx < names.length ? names[cursorIdx] : null,
			jv => jv.getValue!(JSONValue[])("profiles"),
			&httpGet, null, 100, null);
	}
	
	// getProfiles
	@safe unittest
	{
		scope client = _createDummyClient("2de5c4b1-09ec-41e7-90ad-add0448b262d");
		auto prof = client.profile;
		with (client.req)
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/app.bsky.actor.getProfile`);
			assert(query == `actor=did%3Aplc%3A2qfqobqz6dzrfa3jv74i6k6m`);
			assert(bodyBinary == ``.representation);
		}
		assert(prof.handle == "dxutjikmg579.hfor.org");
	}
	
	// getProfiles (multi)
	@safe unittest
	{
		scope client = _createDummyClient("0b877230-5d39-4aa1-ab65-b3e5ed2bd23a");
		auto prof = client.profiles(["krzblhls379.vkn.io", "upqbv134.esi.org", "zrlhj265.zlrc.io"]).array;
		with (client.req)
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/app.bsky.actor.getProfiles`
				~ `?actors=krzblhls379.vkn.io&actors=upqbv134.esi.org&actors=zrlhj265.zlrc.io`);
			assert(query == ``);
			assert(bodyBinary == ``.representation);
		}
		assert(prof.length == 3);
		
		client.resetDataSource("0b877230-5d39-4aa1-ab65-b3e5ed2bd23a");
		auto prof2 = client.fetchProfiles(["krzblhls379.vkn.io", "upqbv134.esi.org", "zrlhj265.zlrc.io"]);
		with (client.req)
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/app.bsky.actor.getProfiles`
				~ `?actors=krzblhls379.vkn.io&actors=upqbv134.esi.org&actors=zrlhj265.zlrc.io`);
			assert(query == ``);
			assert(bodyBinary == ``.representation);
		}
		assert(prof2.length == 3);
		assert(prof2[0].handle == "krzblhls379.vkn.io");
	}
	
	/***************************************************************************
	 * Followers
	 * 
	 * - getFollowers : Raw API execution.
	 * - fetchFollowers : Execute multiple APIs to get all data.
	 * - followers : Range to perform API execution when needed.
	 * 
	 * Params:
	 *     name = did or handle, default is user of current session.
	 *     actor = did or handle, default is user of current session.
	 *     cursor = Cursor for sequential data retrieval.
	 *     len = Number of data to be acquired at one time.
	 *     limit = Number to retrieve in a single API run.
	 */
	JSONValue getFollowers(string actor, string cursor = null, size_t limit = 100) @safe
	{
		import std.conv: to;
		return _get("/xrpc/app.bsky.graph.getFollowers", cursor is null
			? ["actor": actor, "limit": limit.to!string()]
			: ["actor": actor, "limit": limit.to!string(), "cursor": cursor]);
	}
	/// ditto
	User[] fetchFollowers(string name, size_t len = 100) @safe
	{
		User[] ret;
		_fetchSequencialData(
			(jv) @safe => jv.getValue!string("cursor", null),
			(jv) @safe => jv.getValue!(JSONValue[])("followers"),
			(jv) @trusted {
				ret.length = ret.length + jv.length;
				foreach (i; 0..jv.length)
					ret[$ - jv.length + i].deserializeFromJson(jv[i]);
			},
			"/xrpc/app.bsky.graph.getFollowers", null, len, ["actor": name]);
		return ret;
	}
	/// ditto
	User[] fetchFollowers() @safe
	{
		return fetchFollowers(_auth.did);
	}
	/// ditto
	FetchRange!User followers(string name, size_t limit = 100) @safe
	{
		return _makeFetchRange!User(
			jv => jv.getValue!string("cursor", null),
			jv => jv.getValue!(JSONValue[])("followers"),
			"/xrpc/app.bsky.graph.getFollowers", null, limit, ["actor": name]);
	}
	/// ditto
	FetchRange!User followers() @safe
	{
		return followers(_auth.did);
	}
	
	// followers/getFollowers
	@safe unittest
	{
		import std.range;
		scope client = _createDummyClient("2db7023a-b2d2-447d-bfce-9e417a17bdac");
		auto prof = client.followers("upqbv134.esi.org", limit: 10).take(5).array;
		with (client.req)
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/app.bsky.graph.getFollowers`);
			assert(query == `limit=10&actor=upqbv134.esi.org`);
			assert(bodyBinary == ``.representation);
		}
		assert(prof.length == 5);
	}
	
	// fetchFollowers
	@safe unittest
	{
		import std.range;
		scope client = _createDummyClient("2db7023a-b2d2-447d-bfce-9e417a17bdac");
		auto prof = client.fetchFollowers("upqbv134.esi.org", 10);
		with (client.req)
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/app.bsky.graph.getFollowers`);
			assert(query == `limit=20&actor=upqbv134.esi.org`, query);
			assert(bodyBinary == ``.representation);
		}
		assert(prof.length == 10);
	}
	
	/***************************************************************************
	 * Follows
	 * 
	 * - getFollows : Raw API execution
	 * - fetchFollows : Execute multiple APIs to get all data.
	 * - follows : Range to perform API execution when needed.
	 * 
	 * Params:
	 *     name = did or handle, default is user of current session.
	 *     actor = did or handle, default is user of current session.
	 *     cursor = Cursor for sequential data retrieval.
	 *     limit = Number to retrieve in a single API run.
	 */
	JSONValue getFollows(string actor, string cursor = null, size_t limit = 50) @safe
	{
		import std.conv: to;
		return _get("/xrpc/app.bsky.graph.getFollows", cursor is null
			? ["actor": actor, "limit": limit.to!string()]
			: ["actor": actor, "limit": limit.to!string(), "cursor": cursor]);
	}
	/// ditto
	User[] fetchFollows(string name, size_t len = 100) @safe
	{
		User[] ret;
		void append(JSONValue[] jv)
		{
			ret.length = ret.length + jv.length;
			foreach (i; 0..jv.length)
				ret[$ - jv.length + i].deserializeFromJson(jv[i]);
		}
		_fetchSequencialData(
			(jv) @safe => jv.getValue!string("cursor", null),
			(jv) @safe => jv.getValue!(JSONValue[])("follows"),
			(jv) @trusted {
				ret.length = ret.length + jv.length;
				foreach (i; 0..jv.length)
					ret[$ - jv.length + i].deserializeFromJson(jv[i]);
			},
			"/xrpc/app.bsky.graph.getFollows", null, len, ["actor": name]);
		return ret;
	}
	/// ditto
	User[] fetchFollows() @safe
	{
		return fetchFollows(_auth.did);
	}
	/// ditto
	FetchRange!User follows(string name, size_t limit = 100) @safe
	{
		return _makeFetchRange!User(
			(jv) @safe => jv.getValue!string("cursor", null),
			(jv) @safe => jv.getValue!(JSONValue[])("follows"),
			"/xrpc/app.bsky.graph.getFollows", null, limit, ["actor": name]);
	}
	/// ditto
	FetchRange!User follows() @safe
	{
		return follows(_auth.did);
	}
	
	// follows/getFollows
	@safe unittest
	{
		import std.range;
		scope client = _createDummyClient("a2a5d059-987f-4f7e-bc7d-db5c7e61519a");
		auto prof = client.follows("upqbv134.esi.org", limit: 10).take(5).array;
		with (client.req)
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/app.bsky.graph.getFollows`);
			assert(query == `limit=10&actor=upqbv134.esi.org`);
			assert(bodyBinary == ``.representation);
		}
		assert(prof.length == 5);
	}
	// fetchFollows
	@safe unittest
	{
		import std.range;
		scope client = _createDummyClient("a2a5d059-987f-4f7e-bc7d-db5c7e61519a");
		auto prof = client.fetchFollows("upqbv134.esi.org", len: 5);
		with (client.req)
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/app.bsky.graph.getFollows`);
			assert(query == `limit=15&actor=upqbv134.esi.org`);
			assert(bodyBinary == ``.representation);
		}
		assert(prof.length == 5);
	}
	
	/***************************************************************************
	 * Result of get timeline
	 */
	struct TimelineResult
	{
		///
		Feed[] feed;
		///
		string cursor;
	}
	/***************************************************************************
	 * Get timeline
	 * 
	 * - getTimeline : Raw API execution.
	 * - fetchTimeline : Execute multiple APIs to get all data.
	 * - timeline : Range to perform API execution when needed.
	 * 
	 * Params
	 *     cursor = Cursor for sequential data retrieval.
	 *     len = Number of data to be acquired at one time.
	 *     limit = Number to retrieve in a single API run.
	 */
	JSONValue getTimeline(string cursor, size_t limit) @safe
	{
		import std.conv: to;
		auto res = _get("/xrpc/app.bsky.feed.getTimeline", cursor is null
			? ["limit": limit.to!string()]
			: ["limit": limit.to!string(), "cursor": cursor]);
		_enforceHttpRes(res);
		return res;
	}
	/// ditto
	TimelineResult fetchTimeline(string cursor, size_t len = 100) @safe
	{
		TimelineResult ret;
		ret.cursor = _fetchSequencialData(
			(jv) @safe => jv.getValue!string("cursor", null),
			(jv) @safe => jv.getValue!(JSONValue[])("feed"),
			(jv) @trusted {
				ret.feed.length = ret.feed.length + jv.length;
				foreach (i; 0..jv.length)
					ret.feed[$ - jv.length + i].deserializeFromJson(jv[i]);
			},
			"/xrpc/app.bsky.feed.getTimeline", cursor, len, null);
		return ret;
	}
	/// ditto
	Feed[] fetchTimeline(size_t len) @safe
	{
		return fetchTimeline(null, len).feed;
	}
	/// ditto
	FetchRange!Feed timeline(string cursor, size_t limit = 100) @safe
	{
		return _makeFetchRange!Feed(
			jv => jv.getValue!string("cursor", null),
			jv => jv.getValue!(JSONValue[])("feed"),
			"/xrpc/app.bsky.feed.getTimeline", cursor, limit, null);
	}
	/// ditto
	FetchRange!Feed timeline(size_t limit = 100) @safe
	{
		return timeline(null, limit);
	}
	
	// timeline/getTimeline
	@safe unittest
	{
		import std.range;
		scope client = _createDummyClient("657d70c5-eb4d-4b33-ab35-86a1589c2e9a");
		auto timeline = client.timeline(limit: 10).take(5).array;
		with (client.req)
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/app.bsky.feed.getTimeline`);
			assert(query == `limit=10`);
			assert(bodyBinary == ``.representation);
		}
		assert(timeline.length == 5);
	}
	
	// fetchTimeline
	@safe unittest
	{
		import std.range;
		scope client = _createDummyClient("657d70c5-eb4d-4b33-ab35-86a1589c2e9a");
		auto timeline = client.fetchTimeline(len: 5);
		with (client.req)
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/app.bsky.feed.getTimeline`);
			assert(query == `limit=15`);
			assert(bodyBinary == ``.representation);
		}
		assert(timeline.length == 5);
	}
	
	///
	alias AuthorFeedResult = TimelineResult;
	/***************************************************************************
	 * Posts and reposts by any user
	 * 
	 * - getAuthorFeed : 
	 * - fetchAuthorFeed : 
	 * - authorFeed : 
	 * 
	 * Params:
	 *     name = did or handle, default is user of current session.
	 *     actor = did or handle, default is user of current session.
	 * 
	 */
	JSONValue getAuthorFeed(string actor, string cursor, size_t limit = 50) @safe
	{
		import std.conv: to;
		auto res = _get("/xrpc/app.bsky.feed.getAuthorFeed", cursor is null
			? ["actor": actor, "limit": limit.to!string()]
			: ["actor": actor, "limit": limit.to!string(), "cursor": cursor]);
		_enforceHttpRes(res);
		return res;
	}
	/// ditto
	AuthorFeedResult fetchAuthorFeed(string name, string cursor, size_t len = 100) @safe
	{
		AuthorFeedResult ret;
		ret.cursor = _fetchSequencialData(
			(jv) @safe => jv.getValue!string("cursor", null),
			(jv) @safe => jv.getValue!(JSONValue[])("feed"),
			(jv) @trusted {
				ret.feed.length = ret.feed.length + jv.length;
				foreach (i; 0..jv.length)
					ret.feed[$ - jv.length + i].deserializeFromJson(jv[i]);
			},
			"/xrpc/app.bsky.feed.getAuthorFeed", cursor, len, null);
		return ret;
	}
	/// ditto
	FetchRange!Feed authorFeed(string name, string cursor, size_t limit = 100) @safe
	{
		return _makeFetchRange!Feed(
			(jv) @safe => jv.getValue!string("cursor", null),
			(jv) @safe => jv.getValue!(JSONValue[])("feed"),
			"/xrpc/app.bsky.feed.getAuthorFeed", cursor, limit, ["actor": name]);
	}
	/// ditto
	FetchRange!Feed authorFeed(string name, size_t limit = 100) @safe
	{
		return authorFeed(name, null, limit);
	}
	/// ditto
	FetchRange!Feed authorFeed(size_t limit = 100) @safe
	{
		return authorFeed(_auth.did, null, limit);
	}
	
	// getAuthorFeed
	@safe unittest
	{
		import std.range;
		scope client = _createDummyClient("89f1adc0-187a-446f-8bae-9c21639622b6");
		auto items = client.authorFeed().take(3);
		with (client.req)
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/app.bsky.feed.getAuthorFeed`);
			assert(query == `limit=100&actor=did%3Aplc%3A2qfqobqz6dzrfa3jv74i6k6m`, query);
			assert(bodyBinary == ``.representation);
		}
		assert(items.walkLength == 2);
	}
	
	///
	alias FeedResult = TimelineResult;
	/***************************************************************************
	 * Posts by any feed
	 */
	JSONValue getFeed(string feedUri, string cursor, size_t limit = 50) @safe
	{
		import std.conv: to;
		auto res = _get("/xrpc/app.bsky.feed.getFeed", cursor is null
			? ["feed": feedUri, "limit": limit.to!string()]
			: ["feed": feedUri, "limit": limit.to!string(), "cursor": cursor]);
		_enforceHttpRes(res);
		return res;
	}
	/// ditto
	FeedResult fetchFeed(string feedUri, string cursor, size_t len = 100) @safe
	{
		FeedResult ret;
		ret.cursor = _fetchSequencialData(
			(jv) @safe => jv.getValue!string("cursor", null),
			(jv) @safe => jv.getValue!(JSONValue[])("feed"),
			(jv) @trusted {
				ret.feed.length = ret.feed.length + jv.length;
				foreach (i; 0..jv.length)
					ret.feed[$ - jv.length + i].deserializeFromJson(jv[i]);
			},
			"/xrpc/app.bsky.feed.getFeed", cursor, len, null);
		return ret;
	}
	/// ditto
	FetchRange!Feed feed(string feedUri, string cursor, size_t limit = 100) @safe
	{
		return _makeFetchRange!Feed(
			(jv) @safe => jv.getValue!string("cursor", null),
			(jv) @safe => jv.getValue!(JSONValue[])("feed"),
			"/xrpc/app.bsky.feed.getFeed", cursor, limit, ["feed": feedUri]);
	}
	/// ditto
	FetchRange!Feed feed(string feedUri, size_t limit = 100) @safe
	{
		return feed(feedUri, null, limit);
	}
	
	///
	alias ListFeedResult = TimelineResult;
	/***************************************************************************
	 * Posts by any feed
	 * 
	 * 
	 */
	JSONValue getListFeed(string listUri, string cursor, size_t limit = 50) @safe
	{
		import std.conv: to;
		auto res = _get("/xrpc/app.bsky.feed.getListFeed", cursor is null
			? ["list": listUri, "limit": limit.to!string()]
			: ["list": listUri, "limit": limit.to!string(), "cursor": cursor]);
		_enforceHttpRes(res);
		return res;
	}
	/// ditto
	auto fetchListFeed(string listUri, string cursor, size_t len) @safe
	{
		ListFeedResult ret;
		ret.cursor = _fetchSequencialData(
			(jv) @safe => jv.getValue!string("cursor", null),
			(jv) @safe => jv.getValue!(JSONValue[])("feed"),
			(jv) @trusted {
				ret.feed.length = ret.feed.length + jv.length;
				foreach (i; 0..jv.length)
					ret.feed[$ - jv.length + i].deserializeFromJson(jv[i]);
			},
			"/xrpc/app.bsky.feed.getListFeed", cursor, len, null);
		return ret;
	}
	/// ditto
	FetchRange!Feed listFeed(string listUri, string cursor, size_t limit = 100) @safe
	{
		return _makeFetchRange!Feed(
			(jv) @safe => jv.getValue!string("cursor", null),
			(jv) @safe => jv.getValue!(JSONValue[])("feed"),
			"/xrpc/app.bsky.feed.getListFeed", cursor, limit, ["list": listUri]);
	}
	/// ditto
	FetchRange!Feed listFeed(string listUri, size_t limit = 100) @safe
	{
		return listFeed(listUri, null, limit);
	}
	
	/***************************************************************************
	 * Result of search posts
	 */
	struct SearchPostsResult
	{
		///
		string cursor;
		///
		size_t hitsTotal;
		///
		Post[] posts;
	}
	/***************************************************************************
	 * Search posts
	 */
	JSONValue searchPosts(string query, string cursor, size_t limit = 50) @safe
	{
		import std.conv: to;
		auto res = _get("/xrpc/app.bsky.feed.searchPosts", cursor is null
			? ["q": query, "limit": limit.to!string()]
			: ["q": query, "limit": limit.to!string(), "cursor": cursor]);
		_enforceHttpRes(res);
		return res;
	}
	/// ditto
	SearchPostsResult fetchSearchPosts(string query, string cursor, size_t len = 100) @safe
	{
		SearchPostsResult ret;
		ret.cursor = _fetchSequencialData(
			(jv) @safe {
				ret.hitsTotal = jv.getValue!size_t("hitsTotal", 0);
				return jv.getValue!string("cursor", null);
			},
			(jv) @safe => jv.getValue!(JSONValue[])("posts"),
			(jv) @trusted {
				ret.posts.length = ret.posts.length + jv.length;
				foreach (i; 0..jv.length)
					ret.posts[$ - jv.length + i].deserializeFromJson(jv[i]);
			},
			"/xrpc/app.bsky.feed.searchPosts", cursor, len, ["q": query]);
		return ret;
	}
	/// ditto
	Post[] fetchSearchPosts(string query, size_t len = 100) @safe
	{
		return fetchSearchPosts(query, null, len).posts;
	}
	/// ditto
	FetchRange!Post searchPostItems(string query, string cursor, size_t limit = 100) @safe
	{
		return _makeFetchRange!Post(
			(jv) @safe => jv.getValue!string("cursor", null),
			(jv) @safe => jv.getValue!(JSONValue[])("posts"),
			"/xrpc/app.bsky.feed.searchPosts", cursor, limit, ["q": query]);
	}
	/// ditto
	FetchRange!Post searchPostItems(string query, size_t limit = 100) @safe
	{
		return searchPostItems(query, null, limit);
	}
	
	// searchPostItems/searchPosts
	@safe unittest
	{
		import std.range;
		scope client = _createDummyClient("906a0151-0e10-4cbc-8e42-a8138271a180");
		auto items = client.searchPostItems("#dlang", 5).take(3).array;
		with (client.req)
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/app.bsky.feed.searchPosts`);
			assert(query == `limit=5&q=%23dlang`);
			assert(bodyBinary == ``.representation);
		}
		assert(items.length == 3);
	}
	
	// fetchSearchPosts
	@safe unittest
	{
		import std.range;
		scope client = _createDummyClient("906a0151-0e10-4cbc-8e42-a8138271a180");
		auto items = client.fetchSearchPosts("#dlang", len: 5);
		with (client.req)
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/app.bsky.feed.searchPosts`);
			assert(query == `limit=15&q=%23dlang`);
			assert(bodyBinary == ``.representation);
		}
		assert(items.length == 5);
	}
	
	/***************************************************************************
	 * 
	 */
	JSONValue getPosts(string[] uris) @safe
	in (uris.length > 0 && uris.length <= 25)
	{
		import std.algorithm: map;
		import std.uri: encodeComponent;
		import std.format: format;
		auto encUrls = uris.map!(name => name.encodeComponent()).array;
		auto path = format!"/xrpc/app.bsky.feed.getPosts?%-(uris=%s&%)"(encUrls);
		auto ret = _get(path, null);
		_enforceHttpRes(ret);
		return ret;
	}
	/// ditto
	Post[] fetchPosts(string[] uris) @safe
	{
		return getPostItems(uris).array;
	}
	/// ditto
	auto getPostItems(Range)(Range uris) @safe
	if (is(imported!"std.range".ElementType!Range: string))
	{
		import std.range: chunks;
		import std.algorithm: map, cache, joiner;
		return uris.chunks(25).map!( (uriChunk)
		{
			auto posts = getPosts(uriChunk[]);
			auto pJv = enforce("posts" in posts);
			enforce(pJv.type == JSONType.array);
			return (() @trusted => (*pJv).deserializeFromJson!(Post[]))();
		}).cache.joiner;
	}
	// getPosts
	@safe unittest
	{
		scope client = _createDummyClient("fe3b5003-a909-496f-a5de-97b1186f7bba");
		auto items = client.getPostItems([
			"at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/5ni6rkonpzlx2",
			"at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/hyq6lbnl45len"]).array;
		with (client.req)
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/app.bsky.feed.getPosts`
				~ `?uris=at%3A%2F%2Fdid%3Aplc%3Avibjcyg6myvxdi4ezdrhcsuo%2Fapp.bsky.feed.post%2F5ni6rkonpzlx2`
				~ `&uris=at%3A%2F%2Fdid%3Aplc%3Avibjcyg6myvxdi4ezdrhcsuo%2Fapp.bsky.feed.post%2Fhyq6lbnl45len`);
			assert(query == ``);
			assert(bodyBinary == ``.representation);
		}
		assert(items.length == 2);
		assert(items[0].author.handle == "krzblhls379.vkn.io");
		assert(items[0].record["text"].str == "ほな、試しにもう一回言うてみ。");
		assert(items[0].record["reply"]["parent"]["uri"].str
			== "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/5ni6rkonpzlx2");
		assert(items[1].author.handle == "krzblhls379.vkn.io");
		assert(items[1].record["text"].str == "こんにちは、青空さん！\n空の色、めっちゃ綺麗なブルーやな。\n"
			~ "まるで、海原に浮かぶ船みたいや。\nそやけど、その船はどこへ行くんやろ？\n"
			~ "もしかしたら、宝島を目指してるんかもしれへんな。");
	}
	
	/***************************************************************************
	 * 
	 */
	struct GetRepostResult
	{
		///
		User[] repostedBy;
		///
		string cursor;
	}
	
	/***************************************************************************
	 * Users who has reposted the post
	 */
	JSONValue getRepostedBy(string uri, string cursor, size_t limit = 50) @safe
	{
		import std.conv: to;
		auto res = _get("/xrpc/app.bsky.feed.getRepostedBy", cursor is null
			? ["uri": uri, "limit": limit.to!string()]
			: ["uri": uri, "limit": limit.to!string(), "cursor": cursor]);
		_enforceHttpRes(res);
		return res;
	}
	/// ditto
	GetRepostResult fetchRepostedByUsers(string uri, string cursor, size_t len = 100) @safe
	{
		GetRepostResult ret;
		ret.cursor = _fetchSequencialData(
			(jv) @safe => jv.getValue!string("cursor", null),
			(jv) @safe => jv.getValue!(JSONValue[])("repostedBy"),
			(jv) @trusted {
				ret.repostedBy.length = ret.repostedBy.length + jv.length;
				foreach (i; 0..jv.length)
					ret.repostedBy[$ - jv.length + i].deserializeFromJson(jv[i]);
			},
			"/xrpc/app.bsky.feed.getRepostedBy", cursor, len, ["uri": uri]);
		return ret;
	}
	/// ditto
	User[] fetchRepostedByUsers(string uri, size_t len = 100) @safe
	{
		return fetchRepostedByUsers(uri, null, len).repostedBy;
	}
	/// ditto
	FetchRange!User repostedByUsers(string uri, string cursor, size_t limit = 100) @safe
	{
		return _makeFetchRange!User(
			(jv) @safe => jv.getValue!string("cursor", null),
			(jv) @safe => jv.getValue!(JSONValue[])("repostedBy"),
			"/xrpc/app.bsky.feed.getRepostedBy", cursor, limit, ["uri": uri]);
	}
	/// ditto
	FetchRange!User repostedByUsers(string uri, size_t limit = 100) @safe
	{
		return repostedByUsers(uri, null, limit);
	}
	
	// repostedByUsers/getRepostedBy
	@safe unittest
	{
		import std.range;
		scope client = _createDummyClient("d8b6ad01-f85e-4d8e-bbd0-66347c7025c5");
		auto items = client.repostedByUsers(
			"at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/2mbuau2ygfu4w").array;
		with (client.req)
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/app.bsky.feed.getRepostedBy`);
			assert(query == `limit=100`
				~ `&uri=at%3A%2F%2Fdid%3Aplc%3Amhz3szj7pcjfpzv7pylcmlgx%2Fapp.bsky.feed.post%2F2mbuau2ygfu4w`);
			assert(bodyBinary == ``.representation);
		}
		assert(items.length == 2);
	}
	
	// fetchRepostedBy
	@safe unittest
	{
		import std.range;
		scope client = _createDummyClient("d8b6ad01-f85e-4d8e-bbd0-66347c7025c5");
		auto items = client.fetchRepostedByUsers(
			"at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/2mbuau2ygfu4w",
			len: 5);
		with (client.req)
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/app.bsky.feed.getRepostedBy`);
			assert(query == `limit=15`
				~ `&uri=at%3A%2F%2Fdid%3Aplc%3Amhz3szj7pcjfpzv7pylcmlgx%2Fapp.bsky.feed.post%2F2mbuau2ygfu4w`);
			assert(bodyBinary == ``.representation);
		}
		assert(items.length == 2);
	}
	
	/***************************************************************************
	 * 
	 */
	struct Like
	{
		///
		@systimeConverter
		SysTime indexedAt;
		///
		@systimeConverter
		SysTime createdAt;
		///
		User actor;
	}
	/// ditto
	struct GetLikeResult
	{
		///
		Like[] likes;
		///
		string cursor;
	}
	
	/***************************************************************************
	 * Users who has liked the post
	 */
	JSONValue getLikes(string uri, string cursor, size_t limit = 50) @safe
	{
		import std.conv: to;
		auto res = _get("/xrpc/app.bsky.feed.getLikes", cursor is null
			? ["uri": uri, "limit": limit.to!string()]
			: ["uri": uri, "limit": limit.to!string(), "cursor": cursor]);
		_enforceHttpRes(res);
		return res;
	}
	/// ditto
	GetLikeResult fetchLikeUsers(string uri, string cursor, size_t len = 100) @safe
	{
		import std.conv;
		GetLikeResult ret;
		ret.cursor = _fetchSequencialData(
			(jv) @safe => jv.getValue!string("cursor", null),
			(jv) @safe => jv.getValue!(JSONValue[])("likes"),
			(jv) @trusted {
				ret.likes.length = ret.likes.length + jv.length;
				foreach (i; 0..jv.length)
					ret.likes[$ - jv.length + i].deserializeFromJson(jv[i]);
			},
			"/xrpc/app.bsky.feed.getLikes", cursor, len, ["uri": uri]);
		return ret;
	}
	/// ditto
	Like[] fetchLikeUsers(string uri, size_t len = 100) @safe
	{
		return fetchLikeUsers(uri, null, len).likes;
	}
	/// ditto
	FetchRange!Like likeUsers(string uri, string cursor, size_t limit = 100) @safe
	{
		return _makeFetchRange!Like(
			(jv) @safe => jv.getValue!string("cursor", null),
			(jv) @safe => jv.getValue!(JSONValue[])("likes"),
			"/xrpc/app.bsky.feed.getLikes", cursor, limit, ["uri": uri]);
	}
	/// ditto
	FetchRange!Like likeUsers(string uri, size_t limit = 100) @safe
	{
		return likeUsers(uri, null, limit);
	}
	
	// likeUsers/getLikes
	@safe unittest
	{
		import std.range;
		scope client = _createDummyClient("38ac37c4-c30b-4458-9c62-8c4abe8d71e9");
		auto items = client.likeUsers("at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/2mbuau2ygfu4w").array;
		with (client.req)
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/app.bsky.feed.getLikes`);
			assert(query == `limit=100`
				~ `&uri=at%3A%2F%2Fdid%3Aplc%3Amhz3szj7pcjfpzv7pylcmlgx%2Fapp.bsky.feed.post%2F2mbuau2ygfu4w`);
			assert(bodyBinary == ``.representation);
		}
		assert(items.length == 3);
	}
	
	// fetchLikeUsers
	@safe unittest
	{
		import std.range;
		scope client = _createDummyClient("38ac37c4-c30b-4458-9c62-8c4abe8d71e9");
		auto items = client.fetchLikeUsers("at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/2mbuau2ygfu4w",
			len: 5);
		with (client.req)
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/app.bsky.feed.getLikes`);
			assert(query == `limit=15`
				~ `&uri=at%3A%2F%2Fdid%3Aplc%3Amhz3szj7pcjfpzv7pylcmlgx%2Fapp.bsky.feed.post%2F2mbuau2ygfu4w`);
			assert(bodyBinary == ``.representation);
		}
		assert(items.length == 3);
	}
	
	/***************************************************************************
	 * 
	 */
	struct GetQuotedByResult
	{
		///
		Post[] quotedBy;
		///
		string cursor;
	}
	
	/***************************************************************************
	 * Users who has reposted the post
	 */
	JSONValue getQuotes(string uri, string cursor, size_t limit = 50) @safe
	{
		import std.conv: to;
		auto res = _get("/xrpc/app.bsky.feed.getQuotes", cursor is null
			? ["uri": uri, "limit": limit.to!string()]
			: ["uri": uri, "limit": limit.to!string(), "cursor": cursor]);
		_enforceHttpRes(res);
		return res;
	}
	/// ditto
	GetQuotedByResult fetchQuotedByPosts(string uri, string cursor, size_t len = 100) @safe
	{
		GetQuotedByResult ret;
		ret.cursor = _fetchSequencialData(
			(jv) @safe => jv.getValue!string("cursor", null),
			(jv) @safe => jv.getValue!(JSONValue[])("posts"),
			(jv) @trusted {
				ret.quotedBy.length = ret.quotedBy.length + jv.length;
				foreach (i; 0..jv.length)
					ret.quotedBy[$ - jv.length + i].deserializeFromJson(jv[i]);
			},
			"/xrpc/app.bsky.feed.getQuotes", cursor, len, ["uri": uri]);
		return ret;
	}
	/// ditto
	Post[] fetchQuotedByPosts(string uri, size_t len = 100) @safe
	{
		return fetchQuotedByPosts(uri, null, len).quotedBy;
	}
	/// ditto
	FetchRange!Post quotedByPosts(string uri, string cursor, size_t limit = 100) @safe
	{
		return _makeFetchRange!Post(
			(jv) @safe => jv.getValue!string("cursor", null),
			(jv) @safe => jv.getValue!(JSONValue[])("posts"),
			"/xrpc/app.bsky.feed.getQuotes", cursor, limit, ["uri": uri]);
	}
	/// ditto
	FetchRange!Post quotedByPosts(string uri, size_t limit = 100) @safe
	{
		return quotedByPosts(uri, null, limit);
	}
	
	@safe unittest
	{
		import std.range;
		scope client = _createDummyClient("d6c7c83f-9ab4-4788-9395-1b7a1f4ef587");
		auto items = client.quotedByPosts("at://did:plc:q6bwovkrtermobmtqdscnbas/app.bsky.feed.post/3l6cypch6tk2z",
			limit: 5).take(3).array;
		assert(client.httpc.results.length == 1);
		with (client.req)
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/app.bsky.feed.getQuotes`);
			assert(query == `limit=5`
				~ `&uri=at%3A%2F%2Fdid%3Aplc%3Aq6bwovkrtermobmtqdscnbas%2Fapp.bsky.feed.post%2F3l6cypch6tk2z`);
			assert(bodyBinary == ``.representation);
		}
		assert(items.length == 3);
	}
	
	// fetchLikeUsers
	@safe unittest
	{
		import std.range;
		scope client = _createDummyClient("d6c7c83f-9ab4-4788-9395-1b7a1f4ef587");
		auto items = client.fetchQuotedByPosts("at://did:plc:q6bwovkrtermobmtqdscnbas/app.bsky.feed.post/3l6cypch6tk2z",
			len: 4);
		with (client.req)
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/app.bsky.feed.getQuotes`);
			assert(query == `limit=14`
				~ `&uri=at%3A%2F%2Fdid%3Aplc%3Aq6bwovkrtermobmtqdscnbas%2Fapp.bsky.feed.post%2F3l6cypch6tk2z`);
			assert(bodyBinary == ``.representation);
		}
		assert(items.length == 4);
	}
	
	/***************************************************************************
	 * Resolve handle
	 * 
	 * Params:
	 *     handle = handle of user
	 * Returns:
	 *     did
	 */
	string resolveHandle(string handle) @safe
	{
		auto res = _get("/xrpc/com.atproto.identity.resolveHandle", ["handle": handle]);
		_enforceHttpRes(res);
		return res.getValue("did", "");
	}
	
	// resolveHandle
	@safe unittest
	{
		auto client = _createDummyClient();
		client.httpc.addResult(JSONValue(["did": "did:plc:mhz3szj7pcjfpzv7pylcmlgx"]));
		auto did = client.resolveHandle("upqbv134.esi.org");
		with (client.req)
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/com.atproto.identity.resolveHandle`);
			assert(query == `handle=upqbv134.esi.org`);
			assert(bodyBinary == ``.representation);
		}
		assert(did == "did:plc:mhz3szj7pcjfpzv7pylcmlgx");
	}
	
	/***************************************************************************
	 * Create repository record
	 * 
	 * Params:
	 *     record = Record to create as <collection>
	 *     collection = Collection of record
	 *     validate = Can be set to 'false' to skip Lexicon schema validation of record data,
	 *                'true' to require it, or leave unset to validate only for known Lexicons.
	 *     rkey = The Record Key.
	 *     swapCommit = Compare and swap with the previous commit by CID.
	 * Returns:
	 *     JSON of result data
	 */
	JSONValue createRecord(JSONValue record, string collection, JSONValue opts) @safe
	{
		auto postData = JSONValue([
			"repo": JSONValue(_auth.did),
			"collection": JSONValue(collection),
			"record": record]);
		if (opts.type == JSONType.object)
			convine(postData, opts);
		auto res = _post("/xrpc/com.atproto.repo.createRecord", postData);
		_enforceHttpRes(res);
		return res;
	}
	/// ditto
	JSONValue createRecord(JSONValue record, string collection,
		string rkey, bool validate, string swapCommit) @safe
	{
		JSONValue opts = JSONValue.emptyObject;
		if (rkey !is null)
			opts["rkey"] = JSONValue(rkey);
		if (swapCommit !is null)
			opts["swapCommit"] = JSONValue(swapCommit);
		opts["validate"] = JSONValue(validate);
		return createRecord(record, collection, opts);
	}
	/// ditto
	JSONValue createRecord(JSONValue record,
		string collection = "app.bsky.feed.post",
		string rkey = null, string swapCommit = null) @safe
	{
		JSONValue opts = JSONValue.emptyObject;
		if (rkey !is null)
			opts["rkey"] = JSONValue(rkey);
		if (swapCommit !is null)
			opts["swapCommit"] = JSONValue(swapCommit);
		return createRecord(record, collection, opts);
	}
	
	/***************************************************************************
	 * Get repository record
	 * 
	 * Params:
	 *     authority = Author of repository.
	 *     collection = Collection of records.
	 *     rkey = The Record Key.
	 * Returns:
	 *     JSON of result data
	 */
	JSONValue getRecord(string authority, string collection, string rkey) @safe
	{
		auto record = _get("/xrpc/com.atproto.repo.getRecord", [
			"repo": authority,
			"collection": collection,
			"rkey": rkey]);
		_enforceHttpRes(record);
		return record;
	}
	
	/// ditto
	JSONValue getRecord(AtProtoURI uri) @safe
	{
		return getRecord(uri.authority, uri.collection, uri.rkey);
	}
	
	/// ditto
	JSONValue getRecord(string uri) @safe
	{
		return getRecord(AtProtoURI(uri));
	}
	
	/***************************************************************************
	 * Delete repository record
	 * 
	 * Params:
	 *     collection = Collection of record
	 *     rkey = refresh key of record
	 *     swapRecord = Swap Record
	 *     swapCommit = Swap Commit
	 * Returns:
	 *     JSON of result data
	 */
	void deleteRecord(string collection, string rkey,
		string swapRecord = null, string swapCommit = null) @safe
	{
		auto postData = JSONValue([
			"repo": JSONValue(_auth.did),
			"collection": JSONValue(collection),
			"rkey": JSONValue(rkey)]);
		if (swapRecord.length > 0)
			postData.setValue("swapRecord", swapRecord);
		if (swapCommit.length > 0)
			postData.setValue("swapCommit", swapCommit);
		auto res = _post("/xrpc/com.atproto.repo.deleteRecord", postData);
		_enforceHttpRes(res);
	}
	
	/// ditto
	void deleteRecord(AtProtoURI uri) @safe
	{
		return deleteRecord(uri.collection, uri.rkey);
	}
	
	/// ditto
	void deleteRecord(string uri) @safe
	{
		deleteRecord(AtProtoURI(uri));
	}
	
	/***************************************************************************
	 * Record item of com.atproto.repo.listRecords API
	 */
	struct ListRecordItem
	{
		///
		string uri;
		///
		string cid;
		///
		JSONValue value;
	}
	
	/***************************************************************************
	 * Response of com.atproto.repo.listRecords API
	 */
	struct ListRecords
	{
		///
		ListRecordItem[] records;
		///
		string cursor;
	}
	
	/***************************************************************************
	 * List-up repository records
	 * 
	 * Params:
	 *     authority = Author of repository.
	 *     collection = Collection of record
	 * Returns:
	 *     JSON of result data
	 */
	JSONValue listRecords(string authority, string collection, size_t limit = 50) @safe
	{
		import std.conv;
		auto res = _get("/xrpc/com.atproto.repo.listRecords", [
			"repo": authority,
			"collection": collection,
			"limit": limit.to!string]);
		_enforceHttpRes(res);
		return res;
	}
	/// ditto
	ListRecords fetchRecords(string authority, string collection, string cursor, size_t len = 50) @safe
	{
		ListRecords ret;
		ret.cursor = _fetchSequencialData(
			(jv) @safe => jv.getValue!string("cursor", null),
			(jv) @safe => jv.getValue!(JSONValue[])("records"),
			(jv) @trusted {
				ret.records.length = ret.records.length + jv.length;
				foreach (i; 0..jv.length)
					ret.records[$ - jv.length + i].deserializeFromJson(jv[i]);
			},
			"/xrpc/com.atproto.repo.listRecords", cursor, len, ["repo": authority, "collection": collection]);
		return ret;
	}
	/// ditto
	ListRecordItem[] fetchRecords(string authority, string collection, size_t len = 50) @safe
	{
		return fetchRecords(authority, collection, null, len).records;
	}
	/// ditto
	ListRecordItem[] fetchRecords(string collection, size_t len = 50) @safe
	{
		return fetchRecords(_auth.did, collection, len);
	}
	/// ditto
	FetchRange!ListRecordItem listRecordItems(string authority, string collection, size_t limit = 100) @safe
	{
		return _makeFetchRange!ListRecordItem(
			jv => jv.getValue!string("cursor", null),
			jv => jv.getValue!(JSONValue[])("records"),
			"/xrpc/com.atproto.repo.listRecords", null, limit, ["repo": authority, "collection": collection]);
	}
	/// ditto
	FetchRange!ListRecordItem listRecordItems(string collection, size_t limit = 100) @safe
	{
		return listRecordItems(_auth.did, collection, limit);
	}
	
	@safe unittest
	{
		import std.range;
		scope client = _createDummyClient("74c3ddca-1551-4a04-98f2-09f656fcc341");
		auto records = client.listRecordItems("app.bsky.feed.post").take(5);
		with (client.req(0))
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.listRecords`);
			assert(query == `limit=100&repo=did%3Aplc%3A2qfqobqz6dzrfa3jv74i6k6m&collection=app.bsky.feed.post`, query);
			assert(bodyBinary == ``.representation);
		}
		assert(client.httpc.results.length == 1);
		assert(records.front.uri == "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/hyq6lbnl45len");
		records.popFront();
		assert(client.httpc.results.length == 1);
		assert(records.front.uri == "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/5ni6rkonpzlx2");
		records.popFront();
		assert(client.httpc.results.length == 2);
		with (client.req(1))
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.listRecords`);
			assert(query == `cursor=5ni6rkonpzlx2&limit=100`
				~ `&repo=did%3Aplc%3A2qfqobqz6dzrfa3jv74i6k6m&collection=app.bsky.feed.post`, query);
			assert(bodyBinary == ``.representation);
		}
		assert(records.empty);
	}
	
	/***************************************************************************
	 * Upload blob data
	 * 
	 * Params:
	 *     data = Upload data
	 *     mimeType = Upload data type
	 * Returns:
	 *     JSON of upload result data
	 */
	Blob uploadBlob(immutable(ubyte)[] data, string mimeType) @safe
	{
		auto res = _post("/xrpc/com.atproto.repo.uploadBlob", data, mimeType);
		_enforceHttpRes(res);
		return res["blob"].deserializeFromJson!Blob;
	}
	
	/***************************************************************************
	 * Reply data from URI
	 * 
	 * Params:
	 *     uri = URI of reply parent
	 * Returns:
	 *     PostRef: bsky.lexcons.com.atproto.repo.StrongRef
	 */
	StrongRef getRecordRef(string uri) @safe
	{
		import bsky.data: AtProtoURI;
		PostRef ret;
		auto record = getRecord(uri);
		ret.uri = record["uri"].get!string;
		ret.cid = record["cid"].get!string;
		return ret;
	}
	/// ditto
	alias getPostRef = getRecordRef;
	
	/***************************************************************************
	 * Embed data of image
	 */
	struct EmbedImage
	{
		/***********************************************************************
		 * Binary of image
		 * 
		 * Limitation: &lt; 1MB
		 */
		immutable(ubyte)[] image;
		/***********************************************************************
		 * MimeType of image
		 */
		string mimeType;
		/***********************************************************************
		 * Alt text
		 */
		string alt;
		/***********************************************************************
		 * Aspect ratio - width
		 */
		int width;
		/***********************************************************************
		 * Aspect ratio - height
		 */
		int height;
	}
	/// ditto
	app.bsky.embed.Images.Image getEmbedImage(EmbedImage image) @safe
	{
		return app.bsky.embed.Images.Image(
			image: uploadBlob(image.image, image.mimeType),
			alt: image.alt,
			aspectRatio: app.bsky.embed.AspectRatio(image.width, image.height));
	}
	/// ditto
	app.bsky.embed.Images.Image getEmbedImage(immutable(ubyte)[] imageData, string mimeType, string alt,
		int width = 0, int height = 0) @safe
	{
		return app.bsky.embed.Images.Image(
			image: uploadBlob(imageData, mimeType),
			alt: alt,
			aspectRatio: app.bsky.embed.AspectRatio(width, height));
	}
	/// ditto
	app.bsky.embed.Images getEmbedImages(EmbedImage[] images) @safe
	{
		import std.algorithm, std.array;
		return app.bsky.embed.Images(
			images: images.map!(img => getEmbedImage(img)).array);
	}
	
	/***************************************************************************
	 * Embed data of external link
	 */
	struct EmbedExternal
	{
		/***********************************************************************
		 * URL of external link
		 */
		string uri;
		/***********************************************************************
		 * Title of external link
		 */
		string title;
		/***********************************************************************
		 * Descriptions
		 */
		string description;
		/***********************************************************************
		 * Thumbnail of external link
		 */
		immutable(ubyte)[] thumb;
		/***********************************************************************
		 * Thumbnail of external link
		 */
		string thumbMimeType;
	}
	/// ditto
	app.bsky.embed.External getEmbedExternal(EmbedExternal external) @safe
	{
		return app.bsky.embed.External(
			app.bsky.embed.External.External(
				uri: external.uri,
				title: external.title,
				description: external.description,
				thumb: external.thumb.length != 0
					? uploadBlob(external.thumb, external.thumbMimeType)
					: Blob.init)
			);
	}
	/// ditto
	app.bsky.embed.External getEmbedExternal(string uri, string title, string description,
		immutable(ubyte)[] thumb = null, string thumbMimeType = null) @safe
	{
		return getEmbedExternal(EmbedExternal(uri, title, description, thumb, thumbMimeType));
	}
	
	/***************************************************************************
	 * Embed data of external link
	 */
	alias EmbedRecord = StrongRef;
	
	/***************************************************************************
	 * Embed data of external link
	 */
	struct EmbedRecordWithMedia
	{
		/***********************************************************************
		 * URI of record
		 */
		PostRef record;
		/***********************************************************************
		 * Image data
		 */
		alias Media = SumType!(EmbedImage[], EmbedExternal);
		/// ditto
		Media media;
	}
	
	/***************************************************************************
	 * Embed data of image
	 */
	struct EmbedVideo
	{
		/***********************************************************************
		 * Binary of image
		 * 
		 * Limitation: &lt; 1MB
		 */
		immutable(ubyte)[] video;
		/***********************************************************************
		 * MimeType of image
		 */
		string mimeType;
		/***********************************************************************
		 * Alt text
		 */
		string alt;
		/***********************************************************************
		 * Aspect ratio - width
		 */
		int width;
		/***********************************************************************
		 * Aspect ratio - height
		 */
		int height;
		/***********************************************************************
		 * Caption file
		 */
		struct Caption
		{
			///
			string lang;
			///
			immutable(ubyte)[] data;
		}
		/// ditto
		Caption[] captions;
	}
	/// ditto
	app.bsky.embed.Video getEmbedVideo(EmbedVideo video) @safe
	{
		import std.array, std.algorithm;
		return app.bsky.embed.Video(
			video: uploadBlob(video.video, video.mimeType),
			captions: video.captions.map!(cap => app.bsky.embed.Video.Caption(
				file: uploadBlob(cap.data, "text/vtt"), lang: cap.lang)).array,
			alt: video.alt,
			aspectRatio: app.bsky.embed.AspectRatio(video.width, video.height));
	}
	/// ditto
	app.bsky.embed.Video getEmbedVideo(immutable(ubyte)[] videoData, string mimeType, string alt,
		int width = 0, int height = 0) @safe
	{
		return getEmbedVideo(EmbedVideo(videoData, mimeType, alt, width, height));
	}
	
	/***************************************************************************
	 * Reply data from URI
	 * 
	 * Params:
	 *     uri = URI of reply parent
	 * Returns:
	 *     ReplyRef: bsky.lexcons.app.bsky.feed.ReplyRef
	 */
	ReplyRef getReplyRef(string uri) @safe
	{
		import bsky.data: AtProtoURI;
		ReplyRef reply;
		auto parent = getRecord(uri);
		reply.parent = PostRef(parent["uri"].get!string, parent["cid"].get!string);
		if (auto parentReply = "reply" in parent["value"])
		{
			reply.root = PostRef((*parentReply)["root"]["uri"].get!string, (*parentReply)["root"]["cid"].get!string);
		}
		else
		{
			reply.root = reply.parent;
		}
		return reply;
	}
	
	/***************************************************************************
	 * Post message
	 * 
	 * Params:
	 *     record = Record of post
	 *     message = Main text of post
	 *     images = Embed images of post
	 *     opts = Optional parameter of `com.atproto.repo.createRecord` <br />
	 *            (ex1) langs: `JSONValue(["record": JSONValue(["langs": JSONValue(["th", "en-US"])])])` <br />
	 *            (ex2) validation: `JSONValue(["validation": true])` <br />
	 *            (ex3) optional field: `JSONValue(["validation": JSONValue(false), "record": JSONValue(["optionalField": "data"])])`
	 */
	PostRef sendPost(string message, Embed embed,
		ReplyRef replyRef = ReplyRef.init, JSONValue opts = JSONValue.init) @safe
	{
		import std.datetime: Clock;
		import std.algorithm: map;
		auto jvPost = JSONValue([
			"$type": "app.bsky.feed.post",
			"text": message,
			"createdAt": Clock.currTime.toUTC.toISOExtString]);
		auto jvFacets = JSONValue.emptyArray;
		_parseFacet(jvFacets, message);
		if ((() @trusted => jvFacets.array.length)() > 0)
			jvPost["facets"] = jvFacets;
		
		JSONValue _getReplyData(ReplyRef reply) @safe
		{
			return JSONValue([
				"root": JSONValue([
					"uri": reply.root.uri,
					"cid": reply.root.cid]),
				"parent": JSONValue([
					"uri": reply.parent.uri,
					"cid": reply.parent.cid]),
			]);
		}
		if (embed !is Embed.init)
			jvPost["embed"] = embed.serializeToJson();
		if (replyRef !is ReplyRef.init)
			jvPost["reply"] = _getReplyData(replyRef);
		return createRecord(jvPost, "app.bsky.feed.post", opts).deserializeFromJson!PostRef();
	}
	/// ditto
	PostRef sendPost(string message, JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, Embed.init, ReplyRef.init, opts);
	}
	/// ditto
	PostRef sendPost(string message, app.bsky.embed.Images.Image image, JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, Embed(app.bsky.embed.Images(image)), ReplyRef.init, opts);
	}
	/// ditto
	PostRef sendPost(string message, app.bsky.embed.Images images, JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, Embed(images), ReplyRef.init, opts);
	}
	/// ditto
	PostRef sendPost(string message, EmbedImage image, JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, getEmbedImage(image), opts);
	}
	/// ditto
	PostRef sendPost(string message, EmbedImage[] images, JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, getEmbedImages(images), opts);
	}
	/// ditto
	PostRef sendPost(string message, app.bsky.embed.External external, JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, Embed(external), ReplyRef.init, opts);
	}
	/// ditto
	PostRef sendPost(string message, EmbedExternal external, JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, getEmbedExternal(external), opts);
	}
	/// ditto
	PostRef sendPost(string message, app.bsky.embed.Record record, JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, Embed(record), ReplyRef.init, opts);
	}
	/// ditto
	PostRef sendPost(string message, EmbedRecord record, JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, app.bsky.embed.Record(record), opts);
	}
	/// ditto
	PostRef sendPost(string message, app.bsky.embed.RecordWithMedia rwm, JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, Embed(rwm), ReplyRef.init, opts);
	}
	/// ditto
	PostRef sendPost(string message, EmbedRecordWithMedia recordWithMedia, JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, app.bsky.embed.RecordWithMedia(
			record: app.bsky.embed.Record(recordWithMedia.record),
			media: recordWithMedia.media.match!(
				(EmbedImage[] images)    => app.bsky.embed.RecordWithMedia.Media(getEmbedImages(images)),
				(EmbedExternal external) => app.bsky.embed.RecordWithMedia.Media(getEmbedExternal(external)))), opts);
	}
	/// ditto
	PostRef sendPost(string message, EmbedRecord record, EmbedImage image, JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, app.bsky.embed.RecordWithMedia(
			record: app.bsky.embed.Record(record),
			media: app.bsky.embed.RecordWithMedia.Media(getEmbedImages([image]))), opts);
	}
	/// ditto
	PostRef sendPost(string message, EmbedRecord record, EmbedImage[] image, JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, app.bsky.embed.RecordWithMedia(
			record: app.bsky.embed.Record(record),
			media: app.bsky.embed.RecordWithMedia.Media(getEmbedImages(image))), opts);
	}
	/// ditto
	PostRef sendPost(string message, EmbedRecord record, EmbedExternal external, JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, app.bsky.embed.RecordWithMedia(
			record: app.bsky.embed.Record(record),
			media: app.bsky.embed.RecordWithMedia.Media(getEmbedExternal(external))), opts);
	}
	/// ditto
	PostRef sendPost(string message, app.bsky.embed.Video video, JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, Embed(video), ReplyRef.init, opts);
	}
	/// ditto
	PostRef sendPost(string message, EmbedVideo image, JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, getEmbedVideo(image), opts);
	}
	
	// sendPost/createRecord
	@safe unittest
	{
		auto client = _createDummyClient("9dbe5f82-d6a2-4d85-949d-bd6369b2feb5");
		auto postRes = client.sendPost("Post test.");
		with (client.req)
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.createRecord`);
			assert(mimeType == "application/json");
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.feed.post");
			assert(params["record"]["$type"].str == "app.bsky.feed.post");
			assert(params["record"]["text"].str == "Post test.");
		}
		assert(postRes.uri == "at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/sjxklekf4hsir");
		assert(postRes.cid == "ztdjymlhwsoywyrzip7sku4kbwm32v44vpqwj273kb3zggtvuqxp3qg6bi2");
	}
	
	// sendPost (with image)
	@safe unittest
	{
		auto client = _createDummyClient("ce07a958-e5e3-4c3b-94f8-8b1ad427ab0b");
		auto imgBin = readDataSource("d-man.png");
		auto postRes = client.sendPost("画像テスト", [Bluesky.EmbedImage(imgBin, "image/png", "D言語くん")]);
		with (client.req(0))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.uploadBlob`);
			assert(mimeType == `image/png`);
			assert(bodyBinary == imgBin);
		}
		with (client.req(1))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.createRecord`);
			assert(query == "");
			assert(mimeType == "application/json");
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.feed.post");
			assert(params["record"]["embed"]["$type"].str == "app.bsky.embed.images");
			assert((() @trusted => params["record"]["embed"]["images"].array)().length == 1);
			assert(params["record"]["embed"]["images"][0]["image"]["$type"].str == "blob");
			assert(params["record"]["embed"]["images"][0]["image"]["mimeType"].str == "image/png");
			assert(params["record"]["embed"]["images"][0]["image"]["ref"]["$link"].str
				== "mjxrmzdw2ggq2rjuwxan6hm6w36r2nipkecdrvkpkskk5qoo4slwst3xm6f");
			assert(params["record"]["embed"]["images"][0]["image"]["size"].get!uint == imgBin.length);
		}
		assert(postRes.uri == "at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/jmc4tmxvfqx4s");
		assert(postRes.cid == "6e66lvcbu6sw5shqzjex2reh3eus4w4xvrh7q4vccocdrg4epr5ueintmlg");
	}
	
	// sendPost (with external URL)
	@safe unittest
	{
		auto client = _createDummyClient("72a91fe8-1f30-4ebc-a42d-6617642dcbfe");
		auto thumbImg = readDataSource!(immutable(ubyte)[])("d-logo.png");
		client.sendPost("External Link Post Test", EmbedExternal(
			"https://dlang.org",
			"Home - D Programming Language",
			"D is a general-purpose programming language with static typing, systems-level access, and C-like syntax.",
			thumbImg, "image/png"));
		with (client.req(0))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.uploadBlob`);
			assert(mimeType == `image/png`);
			assert(bodyBinary == thumbImg);
		}
		with (client.req(1))
		{
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.feed.post");
			assert(params["record"]["embed"]["$type"].str == "app.bsky.embed.external");
			assert(params["record"]["embed"]["external"]["uri"].str == "https://dlang.org");
			assert(params["record"]["embed"]["external"]["title"].str == "Home - D Programming Language");
			assert(params["record"]["embed"]["external"]["description"].str
				== "D is a general-purpose programming language with static typing"
				 ~ ", systems-level access, and C-like syntax.");
			assert(params["record"]["embed"]["external"]["thumb"]["ref"]["$link"].str
				== client.httpc.results[0].response["blob"]["ref"]["$link"].str);
			assert(params["record"]["text"].str == "External Link Post Test");
		}
	}
	
	// sendPost (with video)
	@safe unittest
	{
		// 動画投稿
		auto client = _createDummyClient("5da79f65-15fe-4701-a837-0e2826e93b05");
		auto videoBin = readDataSource("sample-video.mp4");
		auto postRes = client.sendPost("動画テスト", Bluesky.EmbedVideo(videoBin, "video/mp4", "サンプルビデオ"));
		with (client.req(0))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.uploadBlob`);
			assert(mimeType == `video/mp4`);
			assert(bodyBinary == videoBin);
		}
		with (client.req(1))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.createRecord`);
			assert(query == "");
			assert(mimeType == "application/json");
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.feed.post");
			assert(params["record"]["embed"]["$type"].str == "app.bsky.embed.video");
			assert(params["record"]["embed"]["video"]["$type"].str == "blob");
			assert(params["record"]["embed"]["video"]["mimeType"].str == "video/mp4");
			assert(params["record"]["embed"]["video"]["ref"]["$link"].str
				== "ew7k3lcbapyv7vbturw6xtkrhwp3bejmkpp4mchwfam4fu7xxxjczwz3tou");
			assert(params["record"]["embed"]["video"]["size"].get!uint == videoBin.length);
			assert(params["record"]["embed"]["alt"].str == "サンプルビデオ");
		}
		assert(postRes.uri == "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/ibzjnrqzw33uz");
		assert(postRes.cid == "2jmp7mofugukoo72a4rj4ypcwjhzjnovhmkxqvsrnnugtfpi3qliy3oxudg");
	}
	
	// sendPost (Use optional fields)
	@safe unittest
	{
		auto client = _createDummyClient("885535c2-6087-4b7e-a788-879811463089");
		auto postRes = client.sendPost("Post", JSONValue([
			"validation": JSONValue(false),
			"record": JSONValue(["optionalField": "data"])]));
		with (client.req)
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.createRecord`);
			assert(mimeType == "application/json");
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.feed.post");
			assert(params["record"]["$type"].str == "app.bsky.feed.post");
			assert(params["record"]["text"].str == "Post");
			assert(params["record"]["optionalField"].str == "data");
		}
		assert(postRes.uri == "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/ozgpt6ujloouc");
		assert(postRes.cid == "m4ntkdtmhdz6nway5vg7s2ibfzwq32zrrw6mxxs4n7rzgmuu5cwkz2q7552");
		
	}
	
	/// ditto
	PostRef sendReplyPost(string uri, string message, Embed embed = Embed.init, JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, embed, getReplyRef(uri), opts);
	}
	/// ditto
	PostRef sendReplyPost(string uri, string message, app.bsky.embed.Images images,
		JSONValue opts = JSONValue.init) @safe
	{
		return sendReplyPost(uri, message, Embed(images), opts);
	}
	/// ditto
	PostRef sendReplyPost(string uri, string message, app.bsky.embed.Images.Image[] images,
		JSONValue opts = JSONValue.init) @safe
	{
		return sendReplyPost(uri, message, app.bsky.embed.Images(images), opts);
	}
	/// ditto
	PostRef sendReplyPost(string uri, string message, app.bsky.embed.Images.Image image,
		JSONValue opts = JSONValue.init) @safe
	{
		return sendReplyPost(uri, message, [image], opts);
	}
	/// ditto
	PostRef sendReplyPost(string uri, string message, EmbedImage image, JSONValue opts = JSONValue.init) @safe
	{
		return sendReplyPost(uri, message, getEmbedImage(image), opts);
	}
	/// ditto
	PostRef sendReplyPost(string uri, string message, EmbedImage[] images, JSONValue opts = JSONValue.init) @safe
	{
		return sendReplyPost(uri, message, getEmbedImages(images), opts);
	}
	/// ditto
	PostRef sendReplyPost(string uri, string message, app.bsky.embed.External external,
		JSONValue opts = JSONValue.init) @safe
	{
		return sendReplyPost(uri, message, Embed(external), opts);
	}
	/// ditto
	PostRef sendReplyPost(string uri, string message, EmbedExternal external, JSONValue opts = JSONValue.init) @safe
	{
		return sendReplyPost(uri, message, getEmbedExternal(external), opts);
	}
	/// ditto
	PostRef sendReplyPost(string uri, string message, app.bsky.embed.Record record,
		JSONValue opts = JSONValue.init) @safe
	{
		return sendReplyPost(uri, message, Embed(record), opts);
	}
	/// ditto
	PostRef sendReplyPost(string uri, string message, EmbedRecord record, JSONValue opts = JSONValue.init) @safe
	{
		return sendReplyPost(uri, message, app.bsky.embed.Record(record), opts);
	}
	/// ditto
	PostRef sendReplyPost(string uri, string message, app.bsky.embed.RecordWithMedia recordWithMedia,
		JSONValue opts = JSONValue.init) @safe
	{
		return sendReplyPost(uri, message, Embed(recordWithMedia), opts);
	}
	/// ditto
	PostRef sendReplyPost(string uri, string message, EmbedRecordWithMedia recordWithMedia,
		JSONValue opts = JSONValue.init) @safe
	{
		return sendReplyPost(uri, message, app.bsky.embed.RecordWithMedia(
			record: recordWithMedia.record,
			media: recordWithMedia.media.match!(
				(EmbedImage[] images)    => app.bsky.embed.RecordWithMedia.Media(getEmbedImages(images)),
				(EmbedExternal external) => app.bsky.embed.RecordWithMedia.Media(getEmbedExternal(external)))), opts);
	}
	/// ditto
	PostRef sendReplyPost(string uri, string message, app.bsky.embed.Video video, JSONValue opts = JSONValue.init) @safe
	{
		return sendReplyPost(uri, message, Embed(video), opts);
	}
	/// ditto
	PostRef sendReplyPost(string uri, string message, EmbedVideo video, JSONValue opts = JSONValue.init) @safe
	{
		return sendReplyPost(uri, message, getEmbedVideo(video), opts);
	}
	
	// sendReplyPost/getRecord/createRecord
	@safe unittest
	{
		auto client = _createDummyClient("0b8503cb-4eb7-45ee-8487-80260a3c9284");
		auto postRes = client.sendReplyPost("at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/sjxklekf4hsir",
			"Reply test.");
		with (client.req(0))
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.getRecord`);
			assert(query
				== "rkey=sjxklekf4hsir&repo=did%3Aplc%3Amhz3szj7pcjfpzv7pylcmlgx&collection=app.bsky.feed.post");
			assert(bodyBinary == ``.representation);
		}
		with (client.req(1))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.createRecord`);
			assert(query == "");
			assert(mimeType == "application/json");
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.feed.post");
			assert(params["record"]["$type"].str == "app.bsky.feed.post");
			assert(params["record"]["reply"]["parent"]["cid"].str
				== "ztdjymlhwsoywyrzip7sku4kbwm32v44vpqwj273kb3zggtvuqxp3qg6bi2");
			assert(params["record"]["reply"]["parent"]["uri"].str
				== "at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/sjxklekf4hsir");
			assert(params["record"]["reply"]["root"]["cid"].str
				== "ztdjymlhwsoywyrzip7sku4kbwm32v44vpqwj273kb3zggtvuqxp3qg6bi2");
			assert(params["record"]["reply"]["root"]["uri"].str
				== "at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/sjxklekf4hsir");
			assert(params["record"]["text"].str == "Reply test.");
		}
		assert(postRes.uri == "at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/xlujb5m6o43ot");
		assert(postRes.cid == "uphv4f3bytywlue5vmj7bbcgc45clkdij2s7zsyupjbnfzx34zbiwuu56gy");
	}
	
	// sendReplyPost (with image)
	@safe unittest
	{
		auto client = _createDummyClient("ba2b202c-5657-4b3d-97df-abaff951206c");
		auto imgBin = readDataSource("d-man.png");
		auto postRes = client.sendReplyPost("at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/sjxklekf4hsir",
			"画像テスト", [EmbedImage(imgBin, "image/png", "D言語くん")]);
		with (client.req(0))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.uploadBlob`);
			assert(mimeType == `image/png`);
			assert(bodyBinary == imgBin);
		}
		with (client.req(1))
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.getRecord`);
			assert(query
				== "rkey=sjxklekf4hsir&repo=did%3Aplc%3Amhz3szj7pcjfpzv7pylcmlgx&collection=app.bsky.feed.post");
			assert(bodyBinary == ``.representation);
		}
		with (client.req(2))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.createRecord`);
			assert(query == "");
			assert(mimeType == "application/json");
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.feed.post");
			
			assert(params["record"]["reply"]["parent"]["cid"].str
				== "dx2imfjwbdohkh4re7hh6dguhpczu5mhruw4ofkn6sdmhk4uimas37c5a74");
			assert(params["record"]["reply"]["parent"]["uri"].str
				== "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/5ni6rkonpzlx2");
			assert(params["record"]["reply"]["root"]["cid"].str
				== "dx2imfjwbdohkh4re7hh6dguhpczu5mhruw4ofkn6sdmhk4uimas37c5a74");
			assert(params["record"]["reply"]["root"]["uri"].str
				== "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/5ni6rkonpzlx2");
			
			assert(params["record"]["embed"]["$type"].str == "app.bsky.embed.images");
			assert((() @trusted => params["record"]["embed"]["images"].array)().length == 1);
			assert(params["record"]["embed"]["images"][0]["image"]["$type"].str == "blob");
			assert(params["record"]["embed"]["images"][0]["image"]["mimeType"].str == "image/png");
			assert(params["record"]["embed"]["images"][0]["image"]["ref"]["$link"].str
				== "mjxrmzdw2ggq2rjuwxan6hm6w36r2nipkecdrvkpkskk5qoo4slwst3xm6f");
			assert(params["record"]["embed"]["images"][0]["image"]["size"].get!uint == imgBin.length);
		}
		assert(postRes.uri == "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/gqg7sygic5mii");
		assert(postRes.cid == "5mawkkcu45gctuc4lucf73ozbsg3p6gj6jr5cioz26egrvaw64bgk4kgef3");
	}
	
	// sendReplyPost (with external URL)
	@safe unittest
	{
		auto client = _createDummyClient("d0fa2d8d-9f15-48c8-a3e2-28fcc42ed881");
		auto thumbImg = readDataSource!(immutable(ubyte)[])("d-logo.png");
		auto postRes = client.sendReplyPost("at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/sjxklekf4hsir",
			"External Link Reply Post Test", EmbedExternal(
			"https://dlang.org",
			"Home - D Programming Language",
			"D is a general-purpose programming language with static typing, systems-level access, and C-like syntax.",
			thumbImg, "image/png"));
		with (client.req(0))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.uploadBlob`);
			assert(mimeType == `image/png`);
			assert(bodyBinary == thumbImg);
		}
		with (client.req(1))
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.getRecord`);
			assert(query
				== "rkey=sjxklekf4hsir&repo=did%3Aplc%3Amhz3szj7pcjfpzv7pylcmlgx&collection=app.bsky.feed.post");
			assert(bodyBinary == ``.representation);
		}
		with (client.req(2))
		{
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.feed.post");
			
			assert(params["record"]["reply"]["parent"]["cid"].str
				== "dx2imfjwbdohkh4re7hh6dguhpczu5mhruw4ofkn6sdmhk4uimas37c5a74");
			assert(params["record"]["reply"]["parent"]["uri"].str
				== "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/5ni6rkonpzlx2");
			assert(params["record"]["reply"]["root"]["cid"].str
				== "dx2imfjwbdohkh4re7hh6dguhpczu5mhruw4ofkn6sdmhk4uimas37c5a74");
			assert(params["record"]["reply"]["root"]["uri"].str
				== "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/5ni6rkonpzlx2");
			
			assert(params["record"]["embed"]["$type"].str == "app.bsky.embed.external");
			assert(params["record"]["embed"]["external"]["uri"].str == "https://dlang.org");
			assert(params["record"]["embed"]["external"]["title"].str == "Home - D Programming Language");
			assert(params["record"]["embed"]["external"]["description"].str
				== "D is a general-purpose programming language with static typing"
				 ~ ", systems-level access, and C-like syntax.");
			assert(params["record"]["embed"]["external"]["thumb"]["ref"]["$link"].str
				== client.httpc.results[0].response["blob"]["ref"]["$link"].str);
			assert(params["record"]["text"].str == "External Link Reply Post Test");
		}
		assert(postRes.uri == "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/thtmhnohkv7ew");
		assert(postRes.cid == "uybaf7ict2bgb277cbhklcmhhrcr22q7btbnjzjjjji6crwzvivhkd3wv22");
	}
	
	// sendReplyPost (with image and record)
	@safe unittest
	{
		auto client = _createDummyClient("032bc000-f6f8-4965-a9c7-b66570112870");
		auto imgBin = readDataSource("d-man.png");
		auto recRef = client.getRecordRef("at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/hyq6lbnl45len");
		auto postRes = client.sendReplyPost("at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/5ni6rkonpzlx2",
			"引用と画像のテスト",
			EmbedRecordWithMedia(recRef, EmbedRecordWithMedia.Media([EmbedImage(imgBin, "image/png", "D言語くん")])));
		with (client.req(0))
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.getRecord`);
			assert(query
				== "rkey=hyq6lbnl45len&repo=did%3Aplc%3Avibjcyg6myvxdi4ezdrhcsuo&collection=app.bsky.feed.post");
			assert(bodyBinary == ``.representation);
		}
		with (client.req(1))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.uploadBlob`);
			assert(mimeType == `image/png`);
			assert(bodyBinary == imgBin);
		}
		with (client.req(2))
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.getRecord`);
			assert(query
				== "rkey=5ni6rkonpzlx2&repo=did%3Aplc%3Avibjcyg6myvxdi4ezdrhcsuo&collection=app.bsky.feed.post");
			assert(bodyBinary == ``.representation);
		}
		with (client.req(3))
		{
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.feed.post");
			
			assert(params["record"]["reply"]["parent"]["cid"].str
				== "dx2imfjwbdohkh4re7hh6dguhpczu5mhruw4ofkn6sdmhk4uimas37c5a74");
			assert(params["record"]["reply"]["parent"]["uri"].str
				== "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/5ni6rkonpzlx2");
			assert(params["record"]["reply"]["root"]["cid"].str
				== "dx2imfjwbdohkh4re7hh6dguhpczu5mhruw4ofkn6sdmhk4uimas37c5a74");
			assert(params["record"]["reply"]["root"]["uri"].str
				== "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/5ni6rkonpzlx2");
			
			assert(params["record"]["embed"]["$type"].str == "app.bsky.embed.recordWithMedia");
			
			assert(params["record"]["embed"]["media"]["$type"].str == "app.bsky.embed.images");
			assert(params["record"]["embed"]["media"]["images"][0]["alt"].str == "D言語くん");
			assert(params["record"]["embed"]["media"]["images"][0]["image"]["$type"].str == "blob");
			assert(params["record"]["embed"]["media"]["images"][0]["image"]["mimeType"].str == "image/png");
			assert(params["record"]["embed"]["media"]["images"][0]["image"]["ref"]["$link"].str
				== "mjxrmzdw2ggq2rjuwxan6hm6w36r2nipkecdrvkpkskk5qoo4slwst3xm6f");
			assert(params["record"]["embed"]["media"]["images"][0]["image"]["size"].get!size_t() == 13979);
			
			assert(params["record"]["embed"]["record"]["$type"].str == "app.bsky.embed.record");
			assert(params["record"]["embed"]["record"]["record"]["cid"].str
				== "aykzb74s6m3tj3fvsn777i3zeuefoxkxhwwevxy5juuuaxe24rm26rs6wnf");
			assert(params["record"]["embed"]["record"]["record"]["uri"].str
				== "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/hyq6lbnl45len");
			
			assert(params["record"]["text"].str == "引用と画像のテスト");
		}
		assert(postRes.uri == "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/rgdb72nfe25ym");
		assert(postRes.cid == "xy2frqraadrxv6xxq3bo2x4rxeppbqny4otupfja5cjqrrprnnwiik2ym4i");
	}
	
	// sendReplyPost (with video)
	@safe unittest
	{
		auto client = _createDummyClient("b716e6a4-d8f1-4fab-9073-d66013b3b59a");
		auto videoBin = readDataSource("sample-video.mp4");
		auto postRes = client.sendReplyPost("at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/sjxklekf4hsir",
			"動画テスト", EmbedVideo(videoBin, "video/mp4", "サンプルビデオ"));
		with (client.req(0))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.uploadBlob`);
			assert(mimeType == `video/mp4`);
			assert(bodyBinary == videoBin);
		}
		with (client.req(1))
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.getRecord`);
			assert(query
				== "rkey=sjxklekf4hsir&repo=did%3Aplc%3Amhz3szj7pcjfpzv7pylcmlgx&collection=app.bsky.feed.post");
			assert(bodyBinary == ``.representation);
		}
		with (client.req(2))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.createRecord`);
			assert(query == "");
			assert(mimeType == "application/json");
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.feed.post");
			
			assert(params["record"]["reply"]["parent"]["cid"].str
				== "dx2imfjwbdohkh4re7hh6dguhpczu5mhruw4ofkn6sdmhk4uimas37c5a74");
			assert(params["record"]["reply"]["parent"]["uri"].str
				== "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/5ni6rkonpzlx2");
			assert(params["record"]["reply"]["root"]["cid"].str
				== "dx2imfjwbdohkh4re7hh6dguhpczu5mhruw4ofkn6sdmhk4uimas37c5a74");
			assert(params["record"]["reply"]["root"]["uri"].str
				== "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/5ni6rkonpzlx2");
			
			assert(params["record"]["embed"]["$type"].str == "app.bsky.embed.video");
			assert(params["record"]["embed"]["video"]["$type"].str == "blob");
			assert(params["record"]["embed"]["video"]["mimeType"].str == "video/mp4");
			assert(params["record"]["embed"]["video"]["ref"]["$link"].str
				== "ew7k3lcbapyv7vbturw6xtkrhwp3bejmkpp4mchwfam4fu7xxxjczwz3tou");
			assert(params["record"]["embed"]["video"]["size"].get!uint == videoBin.length);
			assert(params["record"]["embed"]["alt"].str == "サンプルビデオ");
		}
		assert(postRes.uri == "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/2h3dz4kvz4hwa");
		assert(postRes.cid == "ox5yoxngzmhcqacxuvzikrqqypfwswbtf4l2ynhvsip5jjkkoqzo4cv2fb3");
	}
	
	/// ditto
	PostRef sendQuotePost(string uri, string message, JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, Embed(app.bsky.embed.Record(getPostRef(uri))), ReplyRef.init, opts);
	}
	/// ditto
	PostRef sendQuotePost(string uri, string message, app.bsky.embed.Images images,
		JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, Embed(app.bsky.embed.RecordWithMedia(
			record: getPostRef(uri),
			media: app.bsky.embed.RecordWithMedia.Media(images))),
			ReplyRef.init, opts);
	}
	/// ditto
	PostRef sendQuotePost(string uri, string message, app.bsky.embed.Images.Image[] images,
		JSONValue opts = JSONValue.init) @safe
	{
		return sendQuotePost(uri, message, app.bsky.embed.Images(images), opts);
	}
	/// ditto
	PostRef sendQuotePost(string uri, string message, app.bsky.embed.Images.Image image,
		JSONValue opts = JSONValue.init) @safe
	{
		return sendQuotePost(uri, message, [image], opts);
	}
	/// ditto
	PostRef sendQuotePost(string uri, string message, EmbedImage image, JSONValue opts = JSONValue.init) @safe
	{
		return sendQuotePost(uri, message, getEmbedImage(image), opts);
	}
	/// ditto
	PostRef sendQuotePost(string uri, string message, EmbedImage[] images, JSONValue opts = JSONValue.init) @safe
	{
		return sendQuotePost(uri, message, getEmbedImages(images), opts);
	}
	/// ditto
	PostRef sendQuotePost(string uri, string message, app.bsky.embed.External external,
		JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, Embed(app.bsky.embed.RecordWithMedia(
			record: getPostRef(uri),
			media: app.bsky.embed.RecordWithMedia.Media(external))),
			ReplyRef.init, opts);
	}
	/// ditto
	PostRef sendQuotePost(string uri, string message, EmbedExternal external, JSONValue opts = JSONValue.init) @safe
	{
		return sendQuotePost(uri, message, getEmbedExternal(external), opts);
	}
	/// ditto
	PostRef sendQuotePost(string uri, string message, app.bsky.embed.Video video, JSONValue opts = JSONValue.init) @safe
	{
		return sendPost(message, Embed(app.bsky.embed.RecordWithMedia(
			record: getPostRef(uri),
			media: app.bsky.embed.RecordWithMedia.Media(video))),
			ReplyRef.init, opts);
	}
	/// ditto
	PostRef sendQuotePost(string uri, string message, EmbedVideo video, JSONValue opts = JSONValue.init) @safe
	{
		return sendQuotePost(uri, message, getEmbedVideo(video), opts);
	}
	
	// sendQuotePost
	@safe unittest
	{
		auto client = _createDummyClient("ff5bc22f-4dff-480c-a8ee-9faf352a69c7");
		auto postRes = client.sendQuotePost("at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/sjxklekf4hsir",
			"Quote post test");
		with (client.req(0))
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.getRecord`);
			assert(query
				== "rkey=sjxklekf4hsir&repo=did%3Aplc%3Amhz3szj7pcjfpzv7pylcmlgx&collection=app.bsky.feed.post");
			assert(bodyBinary == ``.representation);
		}
		with (client.req(1))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.createRecord`);
			assert(query == "");
			assert(mimeType == "application/json");
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.feed.post");
			assert(params["record"]["$type"].str == "app.bsky.feed.post");
			
			assert(params["record"]["embed"]["$type"].str == "app.bsky.embed.record");
			assert(params["record"]["embed"]["record"]["cid"].str
				== "aykzb74s6m3tj3fvsn777i3zeuefoxkxhwwevxy5juuuaxe24rm26rs6wnf");
			assert(params["record"]["embed"]["record"]["uri"].str
				== "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/hyq6lbnl45len");
			
			assert(params["record"]["text"].str == "Quote post test");
		}
		assert(postRes.uri == "at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/3teavi2n5getc");
		assert(postRes.cid == "clmhhuo6wphqp2pb4cbzcaxs7lzmovr5ldigdm5fzzfbzzkku5yll55j7y4");
	}
	
	// sendQuotePost (with image)
	@safe unittest
	{
		auto client = _createDummyClient("65b058a6-d7eb-414a-8bd8-625331524b6e");
		auto imgBin = readDataSource("d-man.png");
		auto postRes = client.sendQuotePost("at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/sjxklekf4hsir",
			"Quote post test", EmbedImage(imgBin, "image/png", "D言語くん"));
		with (client.req(0))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.uploadBlob`);
			assert(mimeType == `image/png`);
			assert(bodyBinary == imgBin);
		}
		with (client.req(1))
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.getRecord`);
			assert(query
				== "rkey=sjxklekf4hsir&repo=did%3Aplc%3Amhz3szj7pcjfpzv7pylcmlgx&collection=app.bsky.feed.post");
			assert(bodyBinary == ``.representation);
		}
		with (client.req(2))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.createRecord`);
			assert(query == "");
			assert(mimeType == "application/json");
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.feed.post");
			assert(params["record"]["$type"].str == "app.bsky.feed.post");
			assert(params["record"]["embed"]["$type"].str == "app.bsky.embed.recordWithMedia");
			assert(params["record"]["embed"]["record"]["record"]["cid"].str
				== "aykzb74s6m3tj3fvsn777i3zeuefoxkxhwwevxy5juuuaxe24rm26rs6wnf");
			assert(params["record"]["embed"]["record"]["record"]["uri"].str
				== "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/hyq6lbnl45len");
			
			assert(params["record"]["embed"]["media"]["$type"].str == "app.bsky.embed.images");
			assert(params["record"]["embed"]["media"]["images"][0]["alt"].str == "D言語くん");
			assert(params["record"]["embed"]["media"]["images"][0]["image"]["$type"].str == "blob");
			assert(params["record"]["embed"]["media"]["images"][0]["image"]["mimeType"].str == "image/png");
			assert(params["record"]["embed"]["media"]["images"][0]["image"]["ref"]["$link"].str
				== "mjxrmzdw2ggq2rjuwxan6hm6w36r2nipkecdrvkpkskk5qoo4slwst3xm6f");
			assert(params["record"]["embed"]["media"]["images"][0]["image"]["size"].get!size_t() == 13979);
			
			assert(params["record"]["text"].str == "Quote post test");
		}
		assert(postRes.uri == "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/3h546l6tigfco");
		assert(postRes.cid == "pii3oiclei2tdn64oe5cfjihpkvv6o6db4lrzzr2mnefxur7jelrokzzz4q");
	}
	
	// sendQuotePost (with external URL)
	@safe unittest
	{
		auto client = _createDummyClient("04cdf227-7339-486b-bd12-515453cee504");
		auto thumbImg = readDataSource!(immutable(ubyte)[])("d-logo.png");
		auto postRes = client.sendQuotePost("at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/sjxklekf4hsir",
			"External Link Quote Post Test", EmbedExternal(
			"https://dlang.org",
			"Home - D Programming Language",
			"D is a general-purpose programming language with static typing, systems-level access, and C-like syntax.",
			thumbImg, "image/png"));
		with (client.req(0))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.uploadBlob`);
			assert(mimeType == `image/png`);
			assert(bodyBinary == thumbImg);
		}
		with (client.req(1))
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.getRecord`);
			assert(query
				== "rkey=sjxklekf4hsir&repo=did%3Aplc%3Amhz3szj7pcjfpzv7pylcmlgx&collection=app.bsky.feed.post");
			assert(bodyBinary == ``.representation);
		}
		with (client.req(2))
		{
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.feed.post");
			assert(params["record"]["embed"]["$type"].str == "app.bsky.embed.recordWithMedia");
			assert(params["record"]["embed"]["record"]["record"]["cid"].str
				== "aykzb74s6m3tj3fvsn777i3zeuefoxkxhwwevxy5juuuaxe24rm26rs6wnf");
			assert(params["record"]["embed"]["record"]["record"]["uri"].str
				== "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/hyq6lbnl45len");
			
			assert(params["record"]["embed"]["media"]["$type"].str == "app.bsky.embed.external");
			assert(params["record"]["embed"]["media"]["external"]["uri"].str == "https://dlang.org");
			assert(params["record"]["embed"]["media"]["external"]["title"].str == "Home - D Programming Language");
			assert(params["record"]["embed"]["media"]["external"]["description"].str
				== "D is a general-purpose programming language with static typing"
				 ~ ", systems-level access, and C-like syntax.");
			assert(params["record"]["embed"]["media"]["external"]["thumb"]["ref"]["$link"].str
				== client.httpc.results[0].response["blob"]["ref"]["$link"].str);
			
			assert(params["record"]["text"].str == "External Link Quote Post Test");
		}
		assert(postRes.uri == "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/gc5wkr6ugklb6");
		assert(postRes.cid == "7snq6kjyin5s5mth2omrbriiy5bsi4eb5laet6zmyfkn7zt64nqy4vsb2ub");
	}
	
	// sendQuotePost (with video)
	@safe unittest
	{
		auto client = _createDummyClient("77a41238-9d21-4d88-881d-4fbbdec2c4ec");
		auto videoBin = readDataSource("sample-video.mp4");
		auto postRes = client.sendQuotePost("at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/sjxklekf4hsir",
			"Quote video post test", EmbedVideo(videoBin, "video/mp4", "サンプルビデオ"));
		with (client.req(0))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.uploadBlob`);
			assert(mimeType == `video/mp4`);
			assert(bodyBinary == videoBin);
		}
		with (client.req(1))
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.getRecord`);
			assert(query
				== "rkey=sjxklekf4hsir&repo=did%3Aplc%3Amhz3szj7pcjfpzv7pylcmlgx&collection=app.bsky.feed.post");
			assert(bodyBinary == ``.representation);
		}
		with (client.req(2))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.createRecord`);
			assert(query == "");
			assert(mimeType == "application/json");
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.feed.post");
			assert(params["record"]["$type"].str == "app.bsky.feed.post");
			assert(params["record"]["embed"]["$type"].str == "app.bsky.embed.recordWithMedia");
			assert(params["record"]["embed"]["record"]["record"]["cid"].str
				== "dx2imfjwbdohkh4re7hh6dguhpczu5mhruw4ofkn6sdmhk4uimas37c5a74");
			assert(params["record"]["embed"]["record"]["record"]["uri"].str
				== "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/5ni6rkonpzlx2");
			
			assert(params["record"]["embed"]["media"]["$type"].str == "app.bsky.embed.video");
			assert(params["record"]["embed"]["media"]["video"]["$type"].str == "blob");
			assert(params["record"]["embed"]["media"]["video"]["mimeType"].str == "video/mp4");
			assert(params["record"]["embed"]["media"]["video"]["ref"]["$link"].str
				== "ew7k3lcbapyv7vbturw6xtkrhwp3bejmkpp4mchwfam4fu7xxxjczwz3tou");
			assert(params["record"]["embed"]["media"]["video"]["size"].get!size_t() == 362842);
			assert(params["record"]["embed"]["media"]["alt"].str == "サンプルビデオ");
			
			assert(params["record"]["text"].str == "Quote video post test");
		}
		assert(postRes.uri == "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/g3x434awoucyf");
		assert(postRes.cid == "g26lz3rbld5w2clel6a7t5b643ujbxtj2gnmmmtf3ibrpigelhbqsuxhipf");
	}
	
	/***************************************************************************
	 * Delete posts
	 */
	void deletePost(string uri) @safe
	{
		import bsky.data: AtProtoURI;
		auto atUri = AtProtoURI(uri);
		deleteRecord(atUri.collection, atUri.rkey);
	}
	
	// deletePost/deleteRecord
	@safe unittest
	{
		auto client = _createDummyClient("f405c6cd-4fbb-4919-abac-f067dbd51d26");
		client.deletePost("at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.post/xlujb5m6o43ot");
		with (client.req)
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.deleteRecord`);
			assert(mimeType == "application/json");
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.feed.post");
			assert(params["repo"].str == "did:plc:2qfqobqz6dzrfa3jv74i6k6m");
			assert(params["rkey"].str == "xlujb5m6o43ot");
		}
	}
	
	/***************************************************************************
	 * Mark like the post
	 */
	StrongRef markLike(string uri) @trusted
	{
		import std.datetime: Clock;
		app.bsky.feed.Like dat;
		dat.subject = getPostRef(uri);
		dat.createdAt = Clock.currTime.toUTC();
		auto jv = (() @trusted => dat.serializeToJson())();
		return createRecord(jv, "app.bsky.feed.like")
			.deserializeFromJson!StrongRef;
	}
	
	/***************************************************************************
	 * Delete like mark
	 */
	void deleteLike(string uri) @safe
	{
		import std.datetime: Clock;
		auto atUri = AtProtoURI(uri);
		string rkey;
		if (atUri.collection == "app.bsky.feed.post")
		{
			// ポストに対するLikeを削除しようとしている
			auto fullUri = atUri.hasDid ? uri : getRecordRef(uri).uri;
			auto posts = fetchPosts([fullUri]);
			enforce(posts.length == 1);
			enforce(posts[0].viewer.like.length > 0);
			rkey = AtProtoURI(posts[0].viewer.like).rkey;
		}
		else if (atUri.collection == "app.bsky.feed.like")
		{
			// Likeに対して削除しようとしている
			rkey = atUri.rkey;
		}
		else
		{
			enforce(0, "Unsupported URI: " ~ uri);
		}
		deleteRecord("app.bsky.feed.like", rkey);
	}
	
	// markLike/deleteLike
	@safe unittest
	{
		auto client = _createDummyClient("f2862017-1e04-4cf4-b445-4f95ab1962e3");
		auto likeData = client.markLike("at://krzblhls379.vkn.io/app.bsky.feed.post/hyq6lbnl45len");
		with (client.req(0))
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.getRecord`);
			assert(query == "rkey=hyq6lbnl45len&repo=krzblhls379.vkn.io&collection=app.bsky.feed.post");
			assert(bodyBinary == ``.representation);
		}
		with (client.req(1))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.createRecord`);
			assert(mimeType == "application/json");
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.feed.like");
			assert(params["record"]["$type"].str == "app.bsky.feed.like");
			assert(params["record"]["subject"]["cid"].str
				== "aykzb74s6m3tj3fvsn777i3zeuefoxkxhwwevxy5juuuaxe24rm26rs6wnf");
			assert(params["record"]["subject"]["uri"].str
				== "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/hyq6lbnl45len");
			assert(params["repo"].str == "did:plc:2qfqobqz6dzrfa3jv74i6k6m");
		}
		assert(likeData.uri == "at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.like/5hnjyskptmfjq");
		client.deleteLike(likeData.uri);
		with (client.req(2))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.deleteRecord`);
			assert(mimeType == "application/json");
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.feed.like");
			assert(params["rkey"].str == "5hnjyskptmfjq");
			assert(params["repo"].str == "did:plc:2qfqobqz6dzrfa3jv74i6k6m");
		}
	}
	
	/***************************************************************************
	 * Repost posts
	 */
	StrongRef repost(string uri) @safe
	{
		import std.datetime: Clock;
		app.bsky.feed.Repost dat;
		dat.subject = getPostRef(uri);
		dat.createdAt = Clock.currTime.toUTC();
		auto jv = (() @trusted => dat.serializeToJson())();
		return createRecord(jv, "app.bsky.feed.repost")
			.deserializeFromJson!StrongRef;
	}
	
	/***************************************************************************
	 * Delete the repost
	 */
	void deleteRepost(string uri) @safe
	{
		import std.datetime: Clock;
		auto atUri = AtProtoURI(uri);
		string rkey;
		if (atUri.collection == "app.bsky.feed.post")
		{
			// ポストに対するRepostを削除しようとしている
			auto fullUri = atUri.hasDid ? uri : getRecordRef(uri).uri;
			auto posts = fetchPosts([fullUri]);
			enforce(posts.length == 1);
			enforce(posts[0].viewer.repost.length > 0);
			rkey = AtProtoURI(posts[0].viewer.repost).rkey;
		}
		else if (atUri.collection == "app.bsky.feed.repost")
		{
			// Repostに対して削除しようとしている
			rkey = atUri.rkey;
		}
		else
		{
			enforce(0, "Unsupported URI: " ~ uri);
		}
		deleteRecord("app.bsky.feed.repost", rkey);
	}
	
	// repost/deleteRepost
	@safe unittest
	{
		auto client = _createDummyClient("43927f09-ea3f-4ae5-a226-beaf564d2622");
		auto repostData = client.repost("at://krzblhls379.vkn.io/app.bsky.feed.post/hyq6lbnl45len");
		with (client.req(0))
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.getRecord`);
			assert(query == "rkey=hyq6lbnl45len&repo=krzblhls379.vkn.io&collection=app.bsky.feed.post");
			assert(bodyBinary == ``.representation);
		}
		with (client.req(1))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.createRecord`);
			assert(mimeType == "application/json");
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.feed.repost");
			assert(params["record"]["$type"].str == "app.bsky.feed.repost");
			assert(params["record"]["subject"]["cid"].str
				== "aykzb74s6m3tj3fvsn777i3zeuefoxkxhwwevxy5juuuaxe24rm26rs6wnf");
			assert(params["record"]["subject"]["uri"].str
				== "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.feed.post/hyq6lbnl45len");
			assert(params["repo"].str == "did:plc:2qfqobqz6dzrfa3jv74i6k6m");
		}
		assert(repostData.uri == "at://did:plc:mhz3szj7pcjfpzv7pylcmlgx/app.bsky.feed.repost/nbcyhg4w2kz7w");
		client.deleteRepost(repostData.uri);
		with (client.req(2))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.deleteRecord`);
			assert(mimeType == "application/json");
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.feed.repost");
			assert(params["rkey"].str == "nbcyhg4w2kz7w");
			assert(params["repo"].str == "did:plc:2qfqobqz6dzrfa3jv74i6k6m");
		}
	}
	
	
	/***************************************************************************
	 * Follow
	 * 
	 * Params:
	 *     name = Specify the handle or DID of the user you wish to follow
	 * Returns:
	 *     If successful, a reference to the record is returned
	 */
	StrongRef follow(string name) @safe
	{
		import std.datetime: Clock;
		if (!name.startsWith("did:"))
		{
			auto did = resolveHandle(name);
			enforce(did.length != 0, "Cannot resolve handle");
			return follow(did);
		}
		auto jv = JSONValue([
			"$type": "app.bsky.graph.follow",
			"subject": name,
			"createdAt": Clock.currTime.toUTC.toISOExtString]);
		return createRecord(jv, "app.bsky.graph.follow")
			.deserializeFromJson!StrongRef;
	}
	
	/***************************************************************************
	 * Unfollow
	 * 
	 * Params:
	 *     name = Specify the handle or DID of the user you wish to unfollow
	 */
	void unfollow(string name) @safe
	{
		deleteRecord(profile(name).viewer.following);
	}
	// follow/unfollow
	@safe unittest
	{
		auto client = _createDummyClient("c47efab2-6844-4b02-bcca-f214858143e3");
		auto followRes = client.follow("upqbv134.esi.org");
		assert(client.httpc.results.length == 2);
		with (client.req(0))
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/com.atproto.identity.resolveHandle`);
			assert(query == "handle=upqbv134.esi.org");
			assert(bodyBinary == ``.representation);
		}
		with (client.req(1))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.createRecord`);
			assert(mimeType == "application/json");
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.graph.follow");
			assert(params["record"]["$type"].str == "app.bsky.graph.follow");
			assert(params["record"]["subject"].str == "did:plc:mhz3szj7pcjfpzv7pylcmlgx");
		}
		assert(followRes.cid == "cx6gaocbuktylkt2pumtw2oj5grkwqbiucuqcnctahbbsn72qrtjugp7er2");
		assert(followRes.uri == "at://did:plc:vibjcyg6myvxdi4ezdrhcsuo/app.bsky.graph.follow/vojhg6o5oliev");
		client.unfollow("upqbv134.esi.org");
		assert(client.httpc.results.length == 4);
		with (client.req(2))
		{
			assert(method == "GET");
			assert(url == `https://bsky.social/xrpc/app.bsky.actor.getProfile`);
			assert(query == "actor=upqbv134.esi.org");
			assert(bodyBinary == ``.representation);
		}
		with (client.req(3))
		{
			assert(method == "POST");
			assert(url == `https://bsky.social/xrpc/com.atproto.repo.deleteRecord`);
			assert(mimeType == "application/json");
			auto params = parseJSON(cast(const char[])bodyBinary);
			assert(params["collection"].str == "app.bsky.graph.follow");
			assert(params["rkey"].str == "vojhg6o5oliev");
			assert(params["repo"].str == "did:plc:2qfqobqz6dzrfa3jv74i6k6m");
		}
	}
}

// Execute with `dub test -d ProvisioningDataSource`
debug (ProvisioningDataSource) @safe unittest
{
	import std;
	import std.process: environment;
	import bsky._internal.httpc;
	auto logFileName = "ut_http.log";
	if (logFileName.exists)
		std.file.remove(logFileName);
	auto logger = new FileLogger(logFileName);
	auto httpc = new CurlHttpClient!()(logger);
	if (!g_utAuth)
		return;
	auto uuid = randomUUID.toString;
	enum dstDir = "tests/.test-data";
	if (dstDir.exists)
		httpc.setResponseJsonRecorder(dstDir.buildPath(uuid ~ ".json"));
	logger.infof("ID: %s", uuid);
	auto client = new Bluesky(g_utAuth, httpc);
	
	version (none)
	{
		// 投稿
		auto postRes = client.sendPost("Hello, Bluesky!");
		client.deletePost(postRes.uri);
	}
	version (none)
	{
		// 画像投稿
		auto imgBin = readDataSource("d-man.png");
		auto postRes = client.sendPost("画像テスト", [Bluesky.EmbedImage(imgBin, "image/png", "D言語くん")]);
		client.deletePost(postRes.uri);
	}
	version (none)
	{
		// 動画投稿
		auto videoBin = readDataSource("sample-video.mp4");
		auto postRes = client.sendPost("動画テスト", Bluesky.EmbedVideo(videoBin, "video/mp4", "サンプルビデオ"));
		client.deletePost(postRes.uri);
	}
	version (none)
	{
		// リンク投稿
		auto thumbImg = readDataSource!(immutable(ubyte)[])("d-logo.png");
		auto postRes = client.sendPost("External Link Post Test", Bluesky.EmbedExternal(
			"https://dlang.org",
			"Home - D Programming Language",
			"D is a general-purpose programming language with static typing, systems-level access, and C-like syntax.",
			thumbImg, "image/png"));
		client.deletePost(postRes.uri);
	}
	
	version (none)
	{
		// 画像返信
		auto imgBin = readDataSource("d-man.png");
		auto postRes = client.sendReplyPost("at://did:plc:vuc5dzl4377xhfuwkcyyfrqc/app.bsky.feed.post/3kpadeirzya27",
			"画像テスト", [Bluesky.EmbedImage(imgBin, "image/png", "D言語くん")]);
		client.deletePost(postRes.uri);
	}
	version (none)
	{
		// 動画投稿
		auto videoBin = readDataSource("sample-video.mp4");
		auto postRes = client.sendReplyPost("at://did:plc:vuc5dzl4377xhfuwkcyyfrqc/app.bsky.feed.post/3kpadeirzya27",
			"動画テスト", Bluesky.EmbedVideo(videoBin, "video/mp4", "サンプルビデオ"));
		client.deletePost(postRes.uri);
	}
	
	version (none)
	{
		// リンク返信
		auto thumbImg = readDataSource!(immutable(ubyte)[])("d-logo.png");
		auto postRes = client.sendReplyPost("at://did:plc:vuc5dzl4377xhfuwkcyyfrqc/app.bsky.feed.post/3kpadeirzya27",
			"External Link Reply Post Test", Bluesky.EmbedExternal(
			"https://dlang.org",
			"Home - D Programming Language",
			"D is a general-purpose programming language with static typing, systems-level access, and C-like syntax.",
			thumbImg, "image/png"));
		client.deletePost(postRes.uri);
	}
	
	version (none)
	{
		// 引用+画像で返信
		auto imgBin = readDataSource("d-man.png");
		auto recRef = client.getRecordRef("at://did:plc:vuc5dzl4377xhfuwkcyyfrqc/app.bsky.feed.post/3krdry3cgzy25");
		auto postRes = client.sendReplyPost("at://did:plc:vuc5dzl4377xhfuwkcyyfrqc/app.bsky.feed.post/3kpadeirzya27",
			"引用と画像のテスト",
			Bluesky.EmbedRecordWithMedia(recRef, Bluesky.EmbedRecordWithMedia.Media(
				[Bluesky.EmbedImage(imgBin, "image/png", "D言語くん")])));
		client.deletePost(postRes.uri);
	}
	
	version (none)
	{
		// 画像で引用ポスト
		auto imgBin = readDataSource("d-man.png");
		auto postRes = client.sendQuotePost("at://did:plc:vuc5dzl4377xhfuwkcyyfrqc/app.bsky.feed.post/3krdry3cgzy25",
			"Quote post test", Bluesky.EmbedImage(imgBin, "image/png", "D言語くん"));
		client.deletePost(postRes.uri);
	}
	
	version (none)
	{
		// リンクで引用ポスト
		auto thumbImg = readDataSource!(immutable(ubyte)[])("d-logo.png");
		auto postRes = client.sendQuotePost("at://did:plc:vuc5dzl4377xhfuwkcyyfrqc/app.bsky.feed.post/3krdry3cgzy25",
			"External Link Reply Post Test", Bluesky.EmbedExternal(
			"https://dlang.org",
			"Home - D Programming Language",
			"D is a general-purpose programming language with static typing, systems-level access, and C-like syntax.",
			thumbImg, "image/png"));
	}
	version (none)
	{
		// 動画引用ポスト
		auto videoBin = readDataSource("sample-video.mp4");
		auto postRes = client.sendQuotePost("at://did:plc:vuc5dzl4377xhfuwkcyyfrqc/app.bsky.feed.post/3kpadeirzya27",
			"Quote video post test", Bluesky.EmbedVideo(videoBin, "video/mp4", "サンプルビデオ"));
		client.deletePost(postRes.uri);
	}
	
	version (none)
	{
		// ポスト一覧取得
		auto records = client.listRecordItems("app.bsky.feed.post").take(5);
		records.popFront();
		records.popFront();
		assert(records.empty);
	}
	
	version (none)
	{
		// フォロー/アンフォロー
		auto followRes = client.follow("mono-shoo.bsky.social");
		writeln(followRes);
		client.unfollow("mono-shoo.bsky.social");
	}
	
	version (none)
	{
		import std.range;
		auto posts = client.quotedByPosts("at://did:plc:vuc5dzl4377xhfuwkcyyfrqc/app.bsky.feed.post/3kpadeirzya27",
			5).take(3);
		foreach (i, p; posts.enumerate)
			writefln("[%d] %s: %s/%s/%s", i, p.uri, p.likeCount, p.repostCount, p.quoteCount);
	}
	
}

//unittest
//{
//	import std.range, std.stdio;
//	auto client = _createDummyClient();
//	client.httpc.addResult(readDataSource!JSONValue("../.test-data/a6d2c441-6464-4481-bdba-40eb5de4184f.json"));
//	auto posts = client.searchPostItems(`("D言語")|dlang`).take(30);
//	foreach (p; posts)
//	{
//		writefln("%s/%s/%s", p.likeCount, p.repostCount, p.quoteCount);
//	}
//	
//}

version (unittest) package(bsky) auto _createDummyClient(string uuid = null,
		string loginDummyDid = "did:plc:2qfqobqz6dzrfa3jv74i6k6m",
		string loginDummyHandle = "dxutjikmg579.hfor.org",
		string loginDummyPassword = "dummy") @trusted
{
	import bsky._internal.httpc;
	import std.file;
	static struct Ret
	{
		DummyHttpClient!() httpc;
		Bluesky            bsky;
		ref const(DummyHttpClient!().HttpRequest) req(size_t idx = 0) @safe
		{
			assert(idx < httpc.results.length);
			return httpc.results[idx].request;
		}
		void resetDataSource(string dsUuid) @safe
		{
			httpc.clearResult();
			addDataSource(dsUuid);
		}
		void addDataSource(string dsUuid) @safe
		{
			httpc.addResult(readDataSource!JSONValue(dsUuid ~ ".json"));
		}
		alias bsky this;
	}
	Ret ret;
	ret.httpc = new DummyHttpClient!();
	ret.bsky = new Bluesky(ret.httpc);
	if (loginDummyDid !is null && loginDummyHandle !is null)
		ret.httpc.addResult(_createDummySession(loginDummyDid, loginDummyHandle).toJson);
	if (loginDummyHandle !is null && loginDummyPassword !is null)
		ret.bsky.login("dxutjikmg579.hfor.org", loginDummyPassword, ret.httpc);
	ret.httpc.clearResult();
	if (uuid !is null)
		ret.resetDataSource(uuid);
	return ret;
}
