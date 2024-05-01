module tests.build_examples;

import std;

int main()
{
	auto dubExe = environment.get("DUB", "dub");
	int result;
	foreach (de; dirEntries("../examples", SpanMode.shallow))
	{
		if (de.name.baseName.startsWith("."))
			continue;
		auto pid = spawnProcess([dubExe, "build"], stdin, stdout, stderr, null, Config.none, de.name);
		auto status = pid.wait();
		if (status == 0)
		{
			writeln(i"$(de.name.baseName) has SUCCEEDED.");
		}
		else
		{
			writeln(i"$(de.name.baseName) has FAILED.");
			result = -1;
		}
	}
	return result;
}
