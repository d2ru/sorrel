import std.stdio;
import sorrel.sdlbackend;

void main()
{
	auto backend = new SdlBackend(1024, 1024, "Sorrel");

	backend.cursor = Cursor.Hand;

	backend.run();
	destroy(backend);
}
