module src.tasks;

import std.datetime, std.algorithm, std.array, std.range, std.parallelism, std.logger, std.exception;
import bsky;
import src.storage;

/*******************************************************************************
 * セッション確立
 * 
 * ファイルが与えられており、存在する場合はそのファイルのセッション情報を使用する
 * ファイルが存在しない場合は環境変数を読み取り、ログインする。
 */
void establishSession(shared AtprotoAuth auth, string accessInfoFile)
{
	import std.file;
	import std.process: environment;
	if (accessInfoFile.length > 0 && accessInfoFile.exists)
	{
		auth.restoreSession(SessionInfo.fromJsonString(std.file.readText(accessInfoFile)));
		auth.updateSession();
	}
	else
	{
		auth.createSession(environment.get("BSKY_LOGINID"), environment.get("BSKY_LOGINPASS"));
		enforce(auth.did.length > 0);
	}
}

/*******************************************************************************
 * セッション保存
 * 
 * ファイルにセッション情報を保存する
 */
void tearupSession(shared AtprotoAuth auth, string accessInfoFile)
{
	import std.file;
	if (accessInfoFile.length > 0 && auth.storeSession().accessJwt.length > 0)
	{
		std.file.write(accessInfoFile, auth.storeSession().toJsonString());
	}
	else
	{
		auth.deleteSession();
	}
}


/*******************************************************************************
 * Get a list of followed users
 */
UserData[] getFollowers(shared AtprotoAuth auth, in UserData[] cacheData = null)
{
	auto client = new Bluesky(auth);
	// getFollowersだけではフォローした時刻を得られないのでgetRecordしてcreatedAtから時刻を得る
	SysTime followTime(string did, string uri)
	{
		auto found = cacheData.find!(ud => ud.did == did);
		if (!found.empty)
			return found.front.modified;
		auto rec = client.getRecord(uri);
		return SysTime.fromISOExtString(rec["value"]["createdAt"].str);
	}
	auto app = appender!(UserData[]);
	foreach (user; client.followers)
	{
		app ~= UserData(
			did:         user.did,
			handle:      user.handle,
			displayName: user.displayName,
			modified:    followTime(user.did, user.viewer.followedBy));
	}
	return app.data;
}

/*******************************************************************************
 * Get a list of following users
 */
UserData[] getFollowing(shared AtprotoAuth auth, in UserData[] cacheData = null)
{
	auto client = new Bluesky(auth);
	auto app = appender!(UserData[]);
	// getFollowsでは登録時間が記録されていない
	// また、アカウント凍結・削除されたものは取得できない
	//foreach (user; client.follows)
	//{
	//	app ~= UserData(
	//		user.did,
	//		user.handle,
	//		user.displayName,
	//		user.indexedAt);
	//}
	foreach (rec; client.listRecordItems("app.bsky.graph.follow", limit: 100))
	{
		app ~= UserData(
			did:      rec.value["subject"].str,
			modified: SysTime.fromISOExtString(rec.value["createdAt"].str));
	}
	// キャッシュに記録済みのものはそれを使用する
	foreach (ref userData; app.data)
	{
		auto found = cacheData.find!(ud => ud.did == userData.did);
		if (!found.empty)
			userData = found.front;
	}
	// キャッシュにないものはgetProfilesを呼び出して取得
	UserData*[string] map;
	auto getProfTargets = app.data.filter!(ud => ud.handle.length == 0);
	if (getProfTargets.empty)
		return app.data;
	foreach (ref ud; getProfTargets.save)
		map[ud.did] = &ud;
	foreach (ref prof; client.profiles(getProfTargets.map!(ud => ud.did).array))
	{
		auto ud = map[prof.did];
		ud.handle = prof.handle;
		ud.displayName = prof.displayName;
	}
	return app.data;
}


/*******************************************************************************
 * Update following/follower list
 * 
 * Params:
 *     auth = Authentication information of Bluesky
 *     lists = Lists of user follows/followed
 */
void updateGraphLists(shared AtprotoAuth auth, ref UserLists lists)
{
	import std.datetime;
	auto taskGetFollowers = task!getFollowers(auth, lists.followers);
	auto taskGetFollowing = task!getFollowing(auth, lists.following);
	taskPool.put(taskGetFollowers);
	taskPool.put(taskGetFollowing);
	auto newFollowers = taskGetFollowers.yieldForce;
	auto newFollowing = taskGetFollowing.yieldForce;
	auto removedByUsers = lists.followers.filter!(user => !newFollowers.canFind!(u => u.did == user.did)).array;
	auto removedUsers = lists.following.filter!(user => !newFollowing.canFind!(u => u.did == user.did)).array;
	lists.followers = newFollowers;
	lists.following = newFollowing;
	foreach(user; removedUsers.filter!(user => !lists.removed.canFind!(u => u.did == user.did)))
	{
		// アンフォローした時刻は取得不可能なので現在時刻を記録
		user.modified = Clock.currTime;
		lists.removed ~= user;
		infof("Removed: %s / %s", user.handle, user.displayName);
	}
	foreach(user; removedByUsers.filter!(user => !lists.removedBy.canFind!(u => u.did == user.did)))
	{
		// アンフォローした時刻は取得不可能なので現在時刻を記録
		user.modified = Clock.currTime;
		lists.removedBy ~= user;
		infof("Removed by: %s / %s", user.handle, user.displayName);
	}
	// 一度リムーブ済みのユーザーを再フォローした場合
	lists.removed = lists.removed.remove!(user => lists.following.canFind!(u => u.did == user.did));
	// 一度リムーブされたユーザーに再フォローされた場合
	lists.removedBy = lists.removedBy.remove!(user => lists.followers.canFind!(u => u.did == user.did));
}
