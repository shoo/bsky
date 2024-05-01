/*******************************************************************************
 * Example of README.md
 */
module src.main;

void main()
{
	import std.stdio, std.process, std.range;
	import bsky;
	auto client = new Bluesky;
	client.login(environment.get("BSKY_LOGINID"), environment.get("BSKY_LOGINPASS"));
	scope (exit)
		client.logout();
	foreach (post; client.timeline.take(100).toMessages)
		writeln(i"$(post.postBy.displayName) < $(post.text)");
}