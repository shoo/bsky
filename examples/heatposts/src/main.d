import src.storage;
import src.tasks;
import bsky;
import std.exception, std.logger, std.algorithm, std.array, std.range;

void main(string[] args)
{
	import std.getopt;
	string accessInfoFile;
	string query;
	size_t count;
	LogLevel logLevel = (cast()sharedLog).logLevel;
	size_t minLikeCnt = 1;
	size_t minRepostCnt = 1;
	args.getopt(std.getopt.config.passThrough,
		"accessInfo",    &accessInfoFile,
		"query|q",       &query,
		"count|n",       &count,
		"logLevel",      &logLevel,
		"minLike",       &minLikeCnt,
		"minRepost",     &minRepostCnt);
	(cast()sharedLog).logLevel = logLevel;
	
	info("Application started.");
	auto auth = new shared AtprotoAuth;
	// Login/Logout/store session
	auth.establishSession(accessInfoFile);
	scope (exit)
		auth.tearupSession(accessInfoFile);
	info("Session established.");
	
	CacheData cache;
	cache.initialize(args);
	scope (exit)
		cache.save();
	
	auto items = searchItems(auth, query, count, cast(shared)cache, minLikeCnt, minRepostCnt);
	struct Data
	{
		UserData user;
		size_t count;
	}
	Data[string] likedUsers;
	Data[string] repostedUsers;
	
	auto heatItems = items.filter!(itm =>
		itm.likeCount >= minLikeCnt && (itm.repostCount + itm.quoteCount) >= minRepostCnt).array;
	foreach (idx, itm; heatItems)
	{
		foreach (user; itm.likedBy)
			likedUsers.update(user.did,
				() => Data(user, 1),
				(ref Data dat){ dat.count++; }
			);
		foreach (user; itm.repostedBy)
			repostedUsers.update(user.did,
				() => Data(user, 1),
				(ref Data dat){ dat.count++; }
			);
		infof("[%d/%d] %s => %d likes, %d reposts", idx + 1, heatItems.length, itm.url, itm.likeCount, itm.repostCount);
	}
	info("Write CSV files.");
	import std.stdio;
	auto foutRepostedBy = File("repostedBy.csv", "w");
	auto foutLikedBy = File("likedBy.csv", "w");
	foreach (uri, dat; likedUsers)
		foutLikedBy.writefln(`%s,%s,%s,"%s",%s,%s`, uri, dat.user.did, dat.user.handle, dat.user.displayName,
			dat.count, "https://bsky.app/profile/" ~ dat.user.handle);
	foreach (uri, dat; repostedUsers)
		foutRepostedBy.writefln(`%s,%s,%s,"%s",%s,%s`, uri, dat.user.did, dat.user.handle, dat.user.displayName,
			dat.count, "https://bsky.app/profile/" ~ dat.user.handle);
	
	info("Make heat data.");
	struct HeatData
	{
		PostData item;
		size_t level1; // 1時間
		size_t level2; // 3時間
		size_t level3; // 6時間
		size_t level4; // 24時間
		size_t level5; // total
	}
	HeatData[string] heatData;
	foreach (itm; items)
		heatData[itm.uri] = HeatData(itm);
	foreach (uri, ref dat; heatData)
	{
		foreach (like; dat.item.likedBy)
		{
			import core.time;
			if (like.modified - dat.item.postAt < 1.hours)
				++dat.level1;
			if (like.modified - dat.item.postAt < 3.hours)
				++dat.level2;
			if (like.modified - dat.item.postAt < 6.hours)
				++dat.level3;
			if (like.modified - dat.item.postAt < 24.hours)
				++dat.level4;
			dat.level5 = dat.item.likeCount;
		}
	}
	info("Write heatdata.html");
	auto foutHeatData = File("heatdata.csv", "w");
	foreach (uri, dat; heatData)
	{
		foutHeatData.writefln(`%s,%s,%s,%s,%s,%s,%s,%s`, uri, dat.item.url, dat.item.handle,
			dat.level1, dat.level2, dat.level3, dat.level4, dat.level5);
	}
	auto foutHeatDataHtml = File("heatdata.html", "w");
	foutHeatDataHtml.writeln("<html><body>");
	bool[string] heatWrote;
	void writeHtmlItem(PostData itm, size_t num, size_t maxNum)
	{
		import std.string: replace;
		with (itm)
		{
			heatWrote[uri] = true;
			foutHeatDataHtml.writefln(`[%d/%d] <a href="https://bsky.app/profile/%s">%s @%s</a>`
				~ ` <a href="%s">%04d/%02d/%02d %02d:%02d:%02d</a><br />`, num + 1, maxNum, handle, displayName, handle,
				url, postAt.year, postAt.month, postAt.day, postAt.hour, postAt.minute, postAt.second);
			foutHeatDataHtml.writefln(`<div>%s</div>`, text.replace("\n", "<br />"));
			foreach (img; imageUrls)
				foutHeatDataHtml.writefln(`<img src="%s" width="480"/>`, img);
			with (heatData[uri])
				foutHeatDataHtml.writefln(`<div>likes: %d in 1 hour / %d in 3 hour `
					~ `/ %d in 6 hour / %d in 24 hour / %d in total</div>`,
					level1, level2, level3, level4, level5);
			foutHeatDataHtml.writeln(`<hr />`);
		}
	}
	void ranking(R)(R r, string text, size_t n)
	{
		foutHeatDataHtml.writefln(`<h1>%s</h1>`, text);
		foutHeatDataHtml.writeln(`<hr />`);
		foreach (i, itm; r.map!(v => v.item).filter!(itm => itm.uri !in heatWrote).take(n).array)
			writeHtmlItem(itm, i, n);
	}
	ranking(heatData.byValue.array.sort!((a, b) => a.level1 > b.level1), "1時間いいね数ベスト10", 10);
	info("1h ranking written.");
	ranking(heatData.byValue.array.sort!((a, b) => a.level2 > b.level2), "3時間いいね数ベスト10", 10);
	info("3h ranking written.");
	ranking(heatData.byValue.array.sort!((a, b) => a.level3 > b.level3), "6時間いいね数ベスト10", 10);
	info("6h ranking written.");
	ranking(heatData.byValue.array.sort!((a, b) => a.level4 > b.level4), "24時間いいね数ベスト10", 10);
	info("24h ranking written.");
	ranking(heatData.byValue.array.sort!((a, b) => a.level5 > b.level5), "総いいね数ベスト10", 10);
	info("total ranking written.");
	foutHeatDataHtml.writeln("</body></html>");
}
