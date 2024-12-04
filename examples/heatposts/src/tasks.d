module src.tasks;

import bsky;
import src.storage;
import std.exception, std.algorithm, std.range, std.array, std.datetime, std.json, std.parallelism, std.logger;

/*******************************************************************************
 * Establishing a session
 * 
 * If a file is given, use the session information from that file if it exists.
 * Or if not, read the environment variables and log in.
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
 * Save the session
 * 
 * Save session information to a file.
 * If no valid filename is given, log out to close the session.
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
 * Search for posts that interested
 */
PostData[] searchItems(shared AtprotoAuth auth, string query, size_t len, shared ref CacheData cache,
	size_t minLikeCnt = 1, size_t minRepostCnt = 1)
{
	auto client = new Bluesky(auth);
	auto app = appender!(PostData[]);
	typeof(task!getLikeUsers(auth, string.init))[string] likeTasks;
	typeof(task!getRepostUsers(auth, string.init))[string] repostTasks;
	typeof(task!getQuoteUsers(auth, string.init))[string] quoteTasks;
	foreach (idx, post; client.searchPostItems(query, limit: 100).take(len).enumerate)
	{
		PostData pd;
		pd = PostData(
			uri: post.uri,
			did: post.author.did,
			handle: post.author.handle,
			displayName: post.author.displayName,
			url: "https://bsky.app/profile/" ~ post.author.handle ~ "/post/" ~ AtProtoURI(post.uri).rkey,
			replyCount: post.replyCount,
			likeCount: post.likeCount,
			repostCount: post.repostCount,
			quoteCount: post.quoteCount,
			text: post.record["text"].str,
			postAt: SysTime.fromISOExtString(post.record["createdAt"].str));
		if ("embed" in post.record
			&& "images" in post.record["embed"])
		{
			foreach (img; post.record["embed"]["images"].array)
			{
				import std.uri;
				pd.imageUrls ~= "https://bsky.social/xrpc/com.atproto.sync.getBlob"
					~ "?did=" ~ encodeComponent(post.author.did)
					~ "&cid=" ~ img["image"]["ref"]["$link"].str;
			}
		}
		if (post.likeCount > 0 && (post.likeCount >= minLikeCnt)
			&& (!cache.getShared("searchItem.likedBy", post.uri, pd.likedBy)
			  || pd.likedBy.length != post.likeCount))
			taskPool.put(likeTasks[post.uri] = task!getLikeUsers(auth, post.uri));
		if (post.repostCount > 0 && (post.repostCount + post.quoteCount >= minRepostCnt)
			&& (!cache.getShared("searchItem.repostedBy", post.uri, pd.repostedBy)
			  || pd.repostedBy.length != post.repostCount))
			taskPool.put(repostTasks[post.uri] = task!getRepostUsers(auth, post.uri));
		if (post.quoteCount > 0 && (post.repostCount + post.quoteCount >= minRepostCnt)
			&& (!cache.getShared("searchItem.quotedBy", post.uri, pd.repostedBy)
			  || pd.repostedBy.length != post.repostCount))
			taskPool.put(quoteTasks[post.uri] = task!getQuoteUsers(auth, post.uri));
		app ~= pd;
		tracef("searchItems progress [%d/%d]", idx+1, len);
	}
	foreach (idx, ref post; app.data)
	{
		if (auto tsk = post.uri in likeTasks)
		{
			post.likedBy = (*tsk).yieldForce;
			cache.setShared("searchItem.likedBy", post.uri, post.likedBy);
		}
		if (auto tsk = post.uri in repostTasks)
		{
			post.repostedBy = (*tsk).yieldForce;
			cache.setShared("searchItem.repostedBy", post.uri, post.repostedBy);
		}
		if (auto tsk = post.uri in quoteTasks)
		{
			post.quotedBy = (*tsk).yieldForce;
			cache.setShared("searchItem.quotedBy", post.uri, post.quotedBy);
		}
		tracef("searchItems detail progress [%d/%d]", idx+1, app.data.length);
	}
	return app.data;
}

/*******************************************************************************
 * Return users who liked
 */
UserData[] getLikeUsers(shared AtprotoAuth auth, string uri)
{
	auto client = new Bluesky(auth);
	auto app = appender!(UserData[]);
	foreach (retryCnt; 0..10)
	{
		app.shrinkTo(0);
		try foreach (like; client.likeUsers(uri, limit: 100))
		{
			app ~= UserData(
				did: like.actor.did,
				handle: like.actor.handle,
				displayName: like.actor.displayName,
				modified: like.createdAt);
		}
		catch (Exception e)
		{
			if (retryCnt <= 3)
			{
				import core.thread;
				Thread.sleep(msecs(500 * (1 << retryCnt)));
				continue;
			}
			throw e;
		}
		break;
	}
	return app.data;
}



/*******************************************************************************
 * Return users who reposted
 */
UserData[] getRepostUsers(shared AtprotoAuth auth, string uri)
{
	auto client = new Bluesky(auth);
	
	SysTime repostTime(string userDid)
	{
		foreach (rec; client.listRecordItems(userDid, "app.bsky.feed.repost", limit: 100))
		{
			if (rec.value["subject"]["uri"].str == uri)
				return SysTime.fromISOExtString(rec.value["createdAt"].str);
		}
		return SysTime.init;
	}
	auto app = appender!(UserData[]);
	foreach (retryCnt; 0..10)
	{
		app.shrinkTo(0);
		try foreach (user; client.repostedByUsers(uri))
		{
			try app ~= UserData(
				did: user.did,
				handle: user.handle,
				displayName: user.displayName,
				modified: repostTime(user.did));
			catch (BlueskyClientException e)
			{
				if (e.status == 400 && e.resError == "InvalidRequest")
					continue;
				throw e;
			}
		}
		catch (Exception e)
		{
			if (retryCnt <= 3)
			{
				import core.thread;
				Thread.sleep(msecs(500 * (1 << retryCnt)));
				continue;
			}
			throw e;
		}
		break;
	}
	return app.data;
}

/*******************************************************************************
 * Return users who posted quotes
 */
UserData[] getQuoteUsers(shared AtprotoAuth auth, string uri)
{
	auto client = new Bluesky(auth);
	auto app = appender!(UserData[]);
	foreach (retryCnt; 0..10)
	{
		app.shrinkTo(0);
		try foreach (post; client.quotedByPosts(uri))
		{
			app ~= UserData(
				did: post.author.did,
				handle: post.author.handle,
				displayName: post.author.displayName,
				modified: SysTime.fromISOExtString(post.record["createdAt"].str));
		}
		catch (Exception e)
		{
			if (retryCnt <= 3)
			{
				import core.thread;
				Thread.sleep(msecs(500 * (1 << retryCnt)));
				continue;
			}
			throw e;
		}
		break;
	}
	return app.data;
}

