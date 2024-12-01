module src.storage;

import std.algorithm, std.array, std.csv, std.string, std.datetime;

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

private alias toMat = r => r.map!array.array;

private string escapeCSV(string txt) @safe
{
	import std.string, std.array;
	if (txt.indexOfAny(",\"\r\n") != -1)
		return `"` ~ txt.replace("\"", "\"\"") ~ `"`;
	return txt;
}

///
string toCSV(string[][] mat) @safe
{
	import std.algorithm, std.format;
	return format!"%-(%-(%-s,%)\n%)"(
		mat.map!(row => row.map!escapeCSV));
}

/// ditto
string toCSV(UserData[] users) @safe
{
	import std.algorithm, std.array;
	return toCSV([["did", "handle", "displayName", "modified"]] ~ users.map!( user => [
		user.did,
		user.handle,
		user.displayName,
		user.modified.toISOExtString(),
		]).array);
}
/// ditto
void toCSVFile(UserData[] users, string csvFile) @safe
{
	import std.file;
	std.file.write(csvFile, toCSV(users));
}

///
UserData[] fromCSV(string[][] mat) @safe
{
	return mat.map!(row => UserData(
		did: row[0],
		handle: row[1],
		displayName: row[2],
		modified: SysTime.fromISOExtString(row[3]))).array;
}

/// ditto
UserData[] fromCSV(string csvContent) @safe
{
	import std.csv, std.range;
	string pop(T)(ref T v) { auto tmp = v.front; v.popFront(); return tmp; }
	return csvContent.csvReader(["did", "handle", "displayName", "modified"]).map!(row => UserData(
		did: pop(row),
		handle: pop(row),
		displayName: pop(row),
		modified: SysTime.fromISOExtString(pop(row)))).array;
}

///
UserData[] fromCSVFile(string csvFile) @safe
{
	import std.file;
	return fromCSV(std.file.readText(csvFile));
}


@safe unittest
{
	import std.string;
	UserData[] ud1;
	ud1 ~= UserData("test1", "testHandle1", "testDisplayName1", SysTime(DateTime(2024, 11, 22, 11, 22, 33)));
	ud1 ~= UserData("test2", "testHandle2", "testDisplayName2,aaa", SysTime(DateTime(2024, 11, 22, 11, 22, 44)));
	ud1 ~= UserData("test3", "testHandle3", "testDisplayName3\naaa", SysTime(DateTime(2024, 11, 22, 11, 22, 55)));
	auto csvStr = toCSV(ud1);
	assert(csvStr == `
		did,handle,displayName,modified
		test1,testHandle1,testDisplayName1,2024-11-22T11:22:33
		test2,testHandle2,"testDisplayName2,aaa",2024-11-22T11:22:44
		test3,testHandle3,"testDisplayName3
		aaa",2024-11-22T11:22:55`.chompPrefix("\n").outdent);
	auto ud2 = fromCSV(csvStr);
	assert(ud2.length == 3);
	assert(ud2[0].handle == "testHandle1");
	assert(ud1 == ud2);
}

/*******************************************************************************
 * 
 */
struct UserLists
{
private:
	// フォローしているユーザー
	string followingListFile   = "following.csv";
	// フォロワー
	string followersListFile   = "followers.csv";
	// フォローから削除したユーザー
	string removedListFile     = "removed.csv";
	// 自分を削除した元フォロワー
	string removedByListFile   = "removedBy.csv";
	// 無視するユーザー
	string ignoredListFile     = "ignored.csv";
	
public:
	/// A list of follows
	UserData[] following;
	/// A list of followers
	UserData[] followers;
	/// A list of users who have unfollowed in the past
	UserData[] removed;
	/// A list of former followers who unfollowed me in the past
	UserData[] removedBy;
	/// A list of ignore users
	UserData[] ignored;
	
	///
	void initialize(ref string[] args)
	{
		import std.getopt;
		import std.file;
		// sqlite3 DB File
		string dbFile;
		
		args.getopt(std.getopt.config.passThrough,
			"followingList", &followingListFile,
			"followersList", &followersListFile,
			"removedList",   &removedListFile,
			"removedByList", &removedByListFile,
			"ignoredList",   &ignoredListFile,
			"db",            &dbFile);
		
		following = followingListFile.exists ? fromCSVFile(followingListFile) : null;
		followers = followersListFile.exists ? fromCSVFile(followersListFile) : null;
		removed   = removedListFile.exists   ? fromCSVFile(removedListFile)   : null;
		removedBy = removedByListFile.exists ? fromCSVFile(removedByListFile) : null;
		ignored   = ignoredListFile.exists   ? fromCSVFile(ignoredListFile)   : null;
		
		version (Have_ddbc) if (dbFile.length > 0)
		{
			import std.stdio;
			stderr.writeln("Currently the DB is not supported yet.");
		}
		
	}
	
	///
	void save()
	{
		following.toCSVFile(followingListFile);
		followers.toCSVFile(followersListFile);
		removed.toCSVFile(removedListFile);
		removedBy.toCSVFile(removedByListFile);
		ignored.toCSVFile(ignoredListFile);
	}
}
