module src.main;

import std.logger;
import std.algorithm, std.array, std.range;
import std.stdio;
import std.datetime;
import std.process;
import bsky;
import bsky._internal.httpc;

void main(string[] args)
{
	import std.getopt;
	string query;
	size_t count = 1000;
	args.getopt(std.getopt.config.passThrough,
		"query|q", &query,
		"count|n", &count);
	if (query is null)
		query = `("D言語")|dlang`;
	//auto logger = new FileLogger("test.log");
	//auto httpc = new CurlHttpClient!()(logger);
	//auto client = new Bluesky("https://public.api.bsky.app", client: httpc);
	auto client = new Bluesky;
	// ログイン不要
	client.login(environment.get("BSKY_LOGINID"), environment.get("BSKY_LOGINPASS"));
	scope (exit)
		client.logout();
	struct Post
	{
		SysTime postAt;
		size_t likeCount;
		SysTime[] likeAt;
	}
	uint[24] todLikeHist;
	uint[7]  dowLikeHist;
	auto likeTimes = appender!(SysTime[]);
	auto posts = appender!(Post[]);
	uint maxOfLikeTod;
	uint maxOfLikeDow;
	import std.format;
	// 
	size_t idx;
	write("Analysing");
	foreach (post; client.searchPostItems(query).take(count))
	{
		//writeln(i"Analysis post[$(idx++)] of $(post.uri)");
		write(".");
		auto p = Post(post.indexedAt, post.likeCount);
		auto st = likeTimes.data.length;
		foreach (like; client.likeUsers(post.uri))
		{
			write(",");
			//writeln(i"Analysis like of $(like.actor.handle)");
			auto tim = like.createdAt.toLocalTime();
			likeTimes ~= tim;
			todLikeHist[tim.hour]++;
			dowLikeHist[tim.dayOfWeek]++;
		}
		p.likeAt = likeTimes.data[st..$].dup;
		posts ~= p;
		stdout.flush();
	}
	writeln(": Done!");
	writeln("--------------------------------------------------");
	maxOfLikeTod = max(todLikeHist[].maxElement, 1);
	maxOfLikeDow = max(dowLikeHist[].maxElement, 1);
	writeln("Time of day Like Histgram");
	foreach (i, val; todLikeHist)
	{
		auto bin = ulong(50 * val) / maxOfLikeTod;
		writef("%4d: ", i);
		foreach (dummy; 0..bin)
			write("█");
		write(" ", val);
		writeln();
		stdout.flush();
	}
	writeln("Day of week Like Histgram");
	foreach (i, val; dowLikeHist)
	{
		auto bin = ulong(50 * val) / maxOfLikeDow;
		writef("%4s: ", ["Sun", "Mon", "Tue", "Wed", "Tur", "Fry", "Sat"][i]);
		foreach (dummy; 0..bin)
			write("█");
		write(" ", val);
		writeln();
		stdout.flush();
	}
	uint[24] todPostHist;
	uint[7]  dowPostHist;
	uint     maxOfPostTod;
	uint     maxOfPostDow;
	foreach (post; posts.data.filter!(p => p.postAt >= (Clock.currTime - 7.days) && p.postAt < Clock.currTime))
	{
		auto tim = post.postAt.toLocalTime();
		todPostHist[tim.hour]++;
		dowPostHist[tim.dayOfWeek]++;
	}
	maxOfPostTod = max(todPostHist[].maxElement, 1);
	maxOfPostDow = max(dowPostHist[].maxElement, 1);
	writeln("Time of day Post Histgram");
	foreach (i, val; todPostHist)
	{
		auto bin = ulong(50 * val) / maxOfPostTod;
		writef("%4d: ", i);
		foreach (dummy; 0..bin)
			write("█");
		write(" ", val);
		writeln();
		stdout.flush();
	}
	writeln("Day of week Post Histgram");
	foreach (i, val; dowPostHist)
	{
		auto bin = ulong(50 * val) / maxOfPostDow;
		writef("%4s: ", ["Sun", "Mon", "Tue", "Wed", "Tur", "Fry", "Sat"][i]);
		foreach (dummy; 0..bin)
			write("█");
		write(" ", val);
		writeln();
		stdout.flush();
	}
	
	writeln("Time of day Like/Post rate Histgram");
	real maxOfLPRTod = 0;
	real maxOfLPRDow = 0;
	maxOfLPRTod = max(iota(0, 24).map!(i => real(todLikeHist[i])/real(max(todPostHist[i], 1))).maxElement, 1);
	maxOfLPRDow = max(iota(0, 7).map!( i => real(dowLikeHist[i])/real(max(dowPostHist[i], 1))).maxElement, 1);
	foreach (i; 0..24)
	{
		auto bin = cast(ulong)(50 * real(todLikeHist[i]) / real(max(todPostHist[i], 1)) / maxOfLPRTod);
		writef("%4d: ", i);
		foreach (dummy; 0..bin)
			write("█");
		write(" ", real(todLikeHist[i]) / max(real(todPostHist[i]), 1));
		writeln();
		stdout.flush();
	}
	writeln("Day of week Like/Post rate Histgram");
	foreach (i; 0..7)
	{
		auto bin = cast(ulong)(50 * real(dowLikeHist[i]) / max(real(dowPostHist[i]),1) / maxOfLPRDow);
		writef("%4s: ", ["Sun", "Mon", "Tue", "Wed", "Tur", "Fry", "Sat"][i]);
		foreach (dummy; 0..bin)
			write("█");
		write(" ", real(dowLikeHist[i]) / max(real(dowPostHist[i]), 1));
		writeln();
		stdout.flush();
	}
	
	uint[25] durLikeHist;
	uint maxOfDurLike = 0;
	struct LikeHistSrcItem
	{
		string uri;
		SysTime postAt;
		SysTime likeTime;
	}
	foreach (post; posts.data.filter!(p => p.postAt >= (Clock.currTime - 7.days) && p.postAt < Clock.currTime))
	{
		foreach (likeTime; post.likeAt)
		{
			auto dur = likeTime - post.postAt;
			// 負の値は無視する
			if (dur < 0.msecs)
				continue;
			durLikeHist[min(dur.total!"hours", 24)]++;
		}
	}
	maxOfDurLike = max(durLikeHist[].maxElement, 1);
	writeln("Time of day Post Histgram");
	foreach (i, val; durLikeHist)
	{
		import std.conv;
		auto bin = cast(ulong)(50 * val / maxOfDurLike);
		writef("%4s: ", i == 24 ? "More" : i.to!string);
		foreach (dummy; 0..bin)
			write("█");
		write(" ", val);
		writeln();
		stdout.flush();
	}
}
