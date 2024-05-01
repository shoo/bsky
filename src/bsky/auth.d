/*******************************************************************************
 * Atproto authenticator
 * 
 * License: BSL-1.0
 */
module bsky.auth;

import std.exception;
import std.json;
import std.datetime;
import bsky._internal;

/*******************************************************************************
 * Login information
 * 
 */
struct LoginInfo
{
	/***************************************************************************
	 * 
	 */
	string identifier;
	/***************************************************************************
	 * 
	 */
	string password;
}

/*******************************************************************************
 * Session information
 * 
 */
struct SessionInfo
{
	/***************************************************************************
	 * 
	 */
	struct DidDoc
	{
		/***********************************************************************
		 * 
		 */
		@name("@context") string[] atContext;
		/***********************************************************************
		 * 
		 */
		string id;
		/***********************************************************************
		 * 
		 */
		string[] alsoKnownAs;
		/***********************************************************************
		 * 
		 */
		struct VerificationMethod
		{
			/*******************************************************************
			 * 
			 */
			string id;
			/*******************************************************************
			 * 
			 */
			string type;
			/*******************************************************************
			 * 
			 */
			string contoroller;
			/*******************************************************************
			 * 
			 */
			string publicKeyMultibase;
		}
		/// ditto
		VerificationMethod[] verificationMethod;
		/***********************************************************************
		 * 
		 */
		struct Service
		{
			/*******************************************************************
			 * 
			 */
			string id;
			/*******************************************************************
			 * 
			 */
			string type;
			/*******************************************************************
			 * 
			 */
			string serviceEndpoint;
		}
		/// ditto
		Service[] service;
		/***********************************************************************
		 * 
		 */
		void opAssign(in DidDoc lhs) @safe
		{
			atContext = lhs.atContext.dup;
			id = lhs.id;
			alsoKnownAs = lhs.alsoKnownAs.dup;
			verificationMethod = lhs.verificationMethod.dup;
			service = lhs.service.dup;
		}
	}
	/// ditto
	DidDoc didDoc;
	/***************************************************************************
	 * 
	 */
	string handle;
	/***************************************************************************
	 * 
	 */
	string did;
	/***************************************************************************
	 * 
	 */
	string accessJwt;
	/***************************************************************************
	 * 
	 */
	string refreshJwt;
	/***************************************************************************
	 * 
	 */
	string email;
	/***************************************************************************
	 * 
	 */
	bool emailConfirmed;
	/***************************************************************************
	 * 
	 */
	bool active;
	/***************************************************************************
	 * 
	 */
	void opAssign(in SessionInfo lhs) @safe
	{
		didDoc = lhs.didDoc;
		handle = lhs.handle;
		did = lhs.did;
		accessJwt = lhs.accessJwt;
		refreshJwt = lhs.refreshJwt;
		email = lhs.email;
		emailConfirmed = lhs.emailConfirmed;
	}
	/***************************************************************************
	 * 
	 */
	static SessionInfo fromJsonString(string json) @safe
	{
		SessionInfo ret;
		ret.deserializeFromJsonString(json);
		return ret;
	}
	/// ditto
	static SessionInfo fromJson(JSONValue json) @safe
	{
		SessionInfo ret;
		ret.deserializeFromJson(json);
		return ret;
	}
	/***************************************************************************
	 * 
	 */
	JSONValue toJson() const @safe
	{
		return this.serializeToJson();
	}
	/// ditto
	string toJsonString() const @safe
	{
		return toJson.toString();
	}
}

/*******************************************************************************
 * Create dummy session for testing
 * 
 */
version (unittest) package(bsky) SessionInfo _createDummySession(
	string did = "did:plc:dummy",
	string handle = "dummy.dummy.dummy",
	string email = "dummy@dummy.dummy",
	DateTime expireAt = DateTime(2999, 12, 31, 23, 59, 59),
	DateTime refreshUntil = DateTime(2999, 12, 31, 23, 59, 59)) @trusted
{
	SessionInfo info;
	info.did = did;
	info.didDoc.id = did;
	info.didDoc.service = [SessionInfo.DidDoc.Service("#atproto_pds",
		"AtprotoPersonalDataServer", "https://hydnum.us-west.host.bsky.network")];
	info.didDoc.verificationMethod = [SessionInfo.DidDoc.VerificationMethod(did ~ "#atproto",
		"Multikey", did, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")];
	info.didDoc.alsoKnownAs = ["at://" ~ handle];
	info.didDoc.atContext = [
		"https://www.w3.org/ns/did/v1",
		"https://w3id.org/security/multikey/v1",
		"https://w3id.org/security/suites/secp256k1-2019/v1"
	];
	import std.datetime;
	import std.string;
	auto currTime = Clock.currTime;
	import bsky._internal.json: JWTValue;
	info.accessJwt = JWTValue("at+jwt", JWTValue.Algorithm.HS256, "dummy".representation, [
		"scope": JSONValue("com.atproto.access"),
		"sub": JSONValue(did),
		"iat": JSONValue(currTime.toUnixTime!long()),
		"exp": JSONValue(new SysTime(expireAt).toUnixTime!long()),
		"aud": JSONValue("did:web:hydnum.us-west.host.bsky.network"),
	]).toString();
	info.refreshJwt = JWTValue("refresh+jwt", JWTValue.Algorithm.HS256, "dummy".representation, [
		"scope": JSONValue("com.atproto.refresh"),
		"sub": JSONValue(did),
		"aud": JSONValue("did:web:bsky.social"),
		"jti": JSONValue("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
		"iat": JSONValue(currTime.toUnixTime!long()),
		"exp": JSONValue(new SysTime(refreshUntil).toUnixTime!long()),
	]).toString();
	info.active = true;
	return info;
}

/*******************************************************************************
 * Bluesky authenticator
 * 
 */
class AtprotoAuth
{
private:
	import std.array: Appender;
	import std.datetime: SysTime;
	import std.typecons: Tuple;
	import bsky._internal.httpc;
	import bsky._internal.misc;
	string _endpoint;
	ManagedShared!HttpClientBase _httpClient;
	ManagedShared!SessionInfo _session;
	struct HttpResult
	{
		JSONValue response;
		uint code;
		string reason;
	}
	
	HttpResult _get(string path, string[string] param, string bearer = null) @safe
	{
		HttpResult ret;
		auto url = _endpoint ~ path;
		with (_httpClient.locked)
		{
			ret.response = get(url, param, () @safe => bearer);
			ret.code = getLastStatusCode;
			ret.reason = getLastStatusReason;
		}
		return ret;
	}
	
	HttpResult _post(string path, JSONValue param, string bearer = null) @safe
	{
		import std.string: representation;
		HttpResult ret;
		auto url = _endpoint ~ path;
		auto p = param is JSONValue.init ? (immutable(ubyte)[]).init : param.toJSON().representation;
		with (_httpClient.locked)
		{
			ret.response = post(url, p, "application/json", () @safe => bearer);
			ret.code = getLastStatusCode;
			ret.reason = getLastStatusReason;
		}
		return ret;
	}
	
public:
	/***************************************************************************
	 * Constructor
	 */
	this(Client = CurlHttpClient!())(string endpoint = "https://bsky.social", Client client = new Client) @safe
	{
		this(endpoint, cast(HttpClientBase)client);
	}
	/// ditto
	this(Client: HttpClientBase)(string endpoint = "https://bsky.social", Client client) @safe
	{
		_httpClient = new ManagedShared!HttpClientBase;
		() @trusted { _httpClient.asUnshared = client; }();
		_endpoint = endpoint;
		_session = new shared ManagedShared!SessionInfo();
	}
	/// ditto
	this(Client = CurlHttpClient!())(string endpoint = "https://bsky.social", Client client = new Client) shared @safe
	{
		this(endpoint, cast(HttpClientBase)client);
	}
	/// ditto
	this(Client: HttpClientBase)(string endpoint = "https://bsky.social", Client client) shared @safe
	{
		_httpClient = new ManagedShared!HttpClientBase;
		() @trusted { _httpClient.asUnshared = client; }();
		_endpoint = endpoint;
		_session = new shared ManagedShared!SessionInfo();
	}
	
	/***************************************************************************
	 * createSession API
	 */
	void createSession(LoginInfo info) @trusted
	{
		auto param = info.serializeToJson();
		auto res = _post("/xrpc/com.atproto.server.createSession", param);
		synchronized (_session)
			_session.asUnshared.deserializeFromJson(res.response);
	}
	/// ditto
	void createSession(LoginInfo info) shared @trusted
	{
		(cast()this).createSession(info);
	}
	/// ditto
	void createSession(string id, string password) @safe
	{
		createSession(LoginInfo(id, password));
	}
	/// ditto
	void createSession(string id, string password) shared @trusted
	{
		(cast()this).createSession(id, password);
	}
	
	/***************************************************************************
	 * refreshSession API
	 */
	void refreshSession() @trusted
	{
		enforce(available);
		Appender!(ubyte[]) app;
		synchronized (_session) with (_session.asUnshared)
		{
			auto res = _post("/xrpc/com.atproto.server.refreshSession", JSONValue.init, refreshJwt);
			enforce(res.code == 200, res.reason ~ "\n\n"
				~ res.response.getValue("error", "Error")
				~ res.response.getValue("message", ": Unknown error occurred."));
			
			static struct RefreshSessionInfo
			{
				string accessJwt;
				string refreshJwt;
				string handle;
				string did;
				SessionInfo.DidDoc didDoc;
			}
			RefreshSessionInfo refreshData;
			refreshData.deserializeFromJson(res.response);
			accessJwt = refreshData.accessJwt;
			refreshJwt = refreshData.refreshJwt;
			handle = refreshData.handle;
			did = refreshData.did;
			didDoc = refreshData.didDoc;
		}
	}
	/// ditto
	void refreshSession() shared
	{
		(cast()this).refreshSession();
	}
	
	/***************************************************************************
	 * deleteSession API
	 */
	void deleteSession() @trusted
	{
		if (!available)
			return;
		
		synchronized (_session)
		{
			auto refreshJwt = _session.asUnshared.refreshJwt;
			auto res = _post("/xrpc/com.atproto.server.deleteSession", JSONValue.init, refreshJwt);
			enforce(res.code == 200, res.reason ~ "\n\n"
				~ res.response.getValue("error", "Error")
				~ res.response.getValue("message", ": Unknown error occurred."));
				_session.asUnshared = SessionInfo.init;
		}
	}
	/// ditto
	void deleteSession() shared @trusted
	{
		(cast()this).deleteSession();
	}
	
	/***************************************************************************
	 * Update strategy
	 */
	enum UpdateStrategy
	{
		/***********************************************************************
		 * 
		 */
		force,
		/***********************************************************************
		 * 
		 */
		expired,
		/***********************************************************************
		 * 
		 */
		before5min,
		/***********************************************************************
		 * 
		 */
		herf
	}
	
	/***************************************************************************
	 * Update session information
	 */
	void updateSession() @trusted
	{
		if (!available)
			return;
		synchronized (_session)
		{
			auto res = _get("/xrpc/com.atproto.server.getSession", null, _session.asUnshared.accessJwt);
			// 400エラー(ExpiredToken)だった場合はリフレッシュトークンを使って更新を試みる
			if (res.code == 400 && res.response.getValue("error", "") == "ExpiredToken")
			{
				refreshSession();
				res = _get("/xrpc/com.atproto.server.getSession", null, _session.asUnshared.accessJwt);
			}
			enforce(res.code == 200, res.reason ~ "\n\n"
				~ res.response.getValue("error", "Error")
				~ res.response.getValue("message", ": Unknown error occurred."));
			static struct UpdateSessionInfo
			{
				string handle;
				string did;
				string email;
				bool emailConfirmed;
				SessionInfo.DidDoc didDoc;
			}
			UpdateSessionInfo dat;
			dat.deserializeFromJson(res.response);
			_session.asUnshared.handle = dat.handle;
			_session.asUnshared.did = dat.did;
			_session.asUnshared.email = dat.email;
			_session.asUnshared.emailConfirmed = dat.emailConfirmed;
			_session.asUnshared.didDoc = dat.didDoc;
		}
	}
	/// ditto
	void updateSession() shared @trusted
	{
		(cast()this).updateSession();
	}
	/// ditto
	void updateSession(UpdateStrategy strategy) @trusted
	{
		import std.datetime: Clock, Duration, minutes;
		if (strategy == UpdateStrategy.force)
			return updateSession();
		auto exp = expire;
		auto currTime = Clock.currTime;
		final switch (strategy)
		{
		case UpdateStrategy.force:
			assert(0);
		case UpdateStrategy.expired:
			if (currTime >= exp)
				return updateSession();
			break;
		case UpdateStrategy.herf:
			if (currTime > exp - ((currTime - exp) / 2))
				return updateSession();
			break;
		case UpdateStrategy.before5min:
			if (currTime > exp - 5.minutes)
				return updateSession();
			break;
		}
	}
	/// ditto
	void updateSession(UpdateStrategy strategy) shared @trusted
	{
		(cast()this).updateSession(strategy);
	}
	
	/***************************************************************************
	 * refreshSession API
	 */
	void restoreSession(in SessionInfo sessionInfo) @trusted
	{
		synchronized (_session)
			_session.asUnshared = sessionInfo;
	}
	/// ditto
	void restoreSession(in SessionInfo sessionInfo) shared @trusted
	{
		(cast()this).restoreSession(sessionInfo);
	}
	/// ditto
	void restoreSessionFromTokens(string accessJwt, string refreshJwt) @trusted
	{
		synchronized (_session)
		{
			_session.asUnshared.accessJwt = accessJwt;
			_session.asUnshared.refreshJwt = refreshJwt;
		}
		updateSession();
	}
	/// ditto
	void restoreSessionFromTokens(string accessJwt, string refreshJwt) shared @trusted
	{
		(cast()this).restoreSessionFromTokens(accessJwt, refreshJwt);
	}
	/// ditto
	void restoreSessionFromRefreshToken(string refreshJwt) @trusted
	{
		synchronized (_session)
		{
			_session.asUnshared.refreshJwt = refreshJwt;
			refreshSession();
			updateSession();
		}
	}
	/// ditto
	void restoreSessionFromRefreshToken(string refreshJwt) shared @trusted
	{
		(cast()this).restoreSessionFromRefreshToken(refreshJwt);
	}
	
	/***************************************************************************
	 * refreshSession API
	 */
	const(SessionInfo) storeSession() const @trusted
	{
		synchronized (_session)
			return _session.asUnshared;
	}
	/// ditto
	const(SessionInfo) storeSession() const shared @trusted
	{
		return (cast()this).storeSession();
	}
	/// ditto
	string storeSessionOnlyRefreshToken() const @trusted
	{
		synchronized (_session)
			return _session.asUnshared.refreshJwt;
	}
	/// ditto
	string storeSessionOnlyRefreshToken() const shared @trusted
	{
		return (cast()this).storeSessionOnlyRefreshToken();
	}
	/// ditto
	Tuple!(string, "accessJwt", string, "refreshJwt") storeSessionOnlyToken() const @trusted
	{
		synchronized (_session) with (_session.asUnshared)
			return typeof(return)(accessJwt, refreshJwt);
	}
	/// ditto
	Tuple!(string, "accessJwt", string, "refreshJwt") storeSessionOnlyToken() const shared @trusted
	{
		return (cast()this).storeSessionOnlyToken();
	}
	
	/***************************************************************************
	 * Available
	 */
	bool available() const @trusted
	{
		synchronized (_session)
			return _session.asUnshared.accessJwt.length > 0;
	}
	/// ditto
	bool available() const shared @trusted
	{
		return (cast()this).available();
	}
	
	/***************************************************************************
	 * createSession API
	 */
	string bearer() const @trusted
	{
		synchronized (_session)
			return _session.asUnshared.accessJwt;
	}
	/// ditto
	string bearer() const shared @trusted
	{
		return (cast()this).bearer();
	}
	
	/***************************************************************************
	 * createSession API
	 */
	string did() const @trusted
	{
		synchronized (_session)
			return _session.asUnshared.did;
	}
	/// ditto
	string did() const shared @trusted
	{
		return (cast()this).did();
	}
	
	/***************************************************************************
	 * Expire duration of auth
	 */
	SysTime expire() const @safe
	{
		import std.base64;
		import std.string: split;
		import std.json: parseJSON;
		import std.exception;
		alias B64 = Base64Impl!('+', '/', Base64.NoPadding);
		string jwt;
		synchronized (_session)
			jwt = (() @trusted => _session.asUnshared)().accessJwt;
		auto values = jwt.split(".");
		enforce(values.length == 3);
		auto jv = parseJSON((() @trusted => cast(string)B64.decode(values[1]))());
		return SysTime.fromUnixTime(jv.getValue("exp", ulong(0))).toLocalTime();
	}
	/// ditto
	SysTime expire() const shared @trusted
	{
		return (cast()this).expire();
	}
	/// ditto
	SysTime refreshExpire() const @safe
	{
		import std.base64;
		import std.string: split;
		import std.json: parseJSON;
		import std.exception;
		alias B64 = Base64Impl!('+', '/', Base64.NoPadding);
		string jwt;
		synchronized (_session)
			jwt = (() @trusted => _session.asUnshared)().refreshJwt;
		auto values = jwt.split(".");
		enforce(values.length == 3);
		auto jv = parseJSON((() @trusted => cast(string)B64.decode(values[1]))());
		return SysTime.fromUnixTime(jv.getValue("exp", ulong(0))).toLocalTime();
	}
	/// ditto
	SysTime refreshExpire() const shared @trusted
	{
		return (cast()this).refreshExpire();
	}
}

debug (ProvisioningDataSource) version (unittest)
{
	/// unittest only
	package(bsky) shared AtprotoAuth g_utAuth;
	
	shared static this()
	{
		import std.process;
		string id = environment.get("BSKYUT_LOGINID");
		string pass = environment.get("BSKYUT_LOGINPASS");
		if (id !is null && pass !is null)
			g_utAuth = new shared AtprotoAuth();
		try if (g_utAuth)
			g_utAuth.createSession(id, pass);
		catch (Exception e)
			g_utAuth = null;
	}
	
	shared static ~this()
	{
		if (g_utAuth)
			g_utAuth.deleteSession();
	}
	
}

@safe unittest
{
	auto auth = new shared AtprotoAuth(client: new DummyHttpClient!());
	auto session = _createDummySession();
	auth.restoreSession(session);
	assert(auth.storeSessionOnlyRefreshToken == session.refreshJwt);
	assert(auth.storeSession.accessJwt == session.accessJwt);
	assert(auth.refreshExpire.year == 2999);
	assert(auth.expire.year == 2999);
	
	auto jv = session.toJson();
	auto dstSession = SessionInfo.fromJson(jv);
	assert(session == dstSession);
	
	auto jvstr = session.toJsonString();
	auto dstSession2 = SessionInfo.fromJsonString(jvstr);
	assert(dstSession2 == dstSession);
}
