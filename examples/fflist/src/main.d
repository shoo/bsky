module src.main;

import std.logger, std.exception;
import bsky;
import src.storage;
import src.tasks;


void main(string[] args)
{
	import std.getopt;
	string accessInfoFile;
	args.getopt(std.getopt.config.passThrough,
		"accessInfo",    &accessInfoFile);
	
	info("Application started.");
	
	auto auth = new shared AtprotoAuth;
	// Login/Logout/store session
	auth.establishSession(accessInfoFile);
	scope (exit)
		auth.tearupSession(accessInfoFile);
	info("Session established.");
	
	UserLists lists;
	lists.initialize(args);
	scope (exit)
		lists.save();
	info("Stored data were loaded.");
	
	updateGraphLists(auth, lists);
	info("Lists updated.");
}
