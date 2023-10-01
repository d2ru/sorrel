module sorrel.sdlbackend;

import std.algorithm: map;
import std.array: array;
import std.exception: enforce;
import std.file: thisExePath;
import std.path: dirName, buildPath;
import std.range: iota;
import std.datetime : Clock;

import std.experimental.logger: Logger, NullLogger, FileLogger, globalLogLevel, LogLevel;

import gfm.math: mat4f, vec3f, vec4f;
import gfm.opengl: OpenGL;
import gfm.sdl2: SDL2, SDL2Window, SDL_Event, SDL_Cursor, SDL_SetCursor, 
	SDL_FreeCursor, SDL_Delay;

/// Cursor shapes available to use in nanogui.  Shape of actual cursor determined by Operating System.
enum Cursor {
	Arrow = 0,  /// The arrow cursor.
	IBeam,      /// The I-beam cursor.
	Crosshair,  /// The crosshair cursor.
	Hand,       /// The hand cursor.
	HResize,    /// The horizontal resize cursor.
	VResize,    /// The vertical resize cursor.
}

class SdlBackend
{
	this(int w, int h, string title)
	{
		/* Avoid locale-related number parsing issues */
		version(Windows) {}
		else {
			import core.stdc.locale;
			setlocale(LC_NUMERIC, "C");
		}

		import gfm.sdl2, gfm.opengl;
		import bindbc.sdl;

		this.width = w;
		this.height = h;

		// create a logger
		import std.stdio : stdout;
		_log = new FileLogger(stdout);

		// load dynamic libraries
		SDLSupport ret = loadSDL();
		if(ret != sdlSupport) {
			if(ret == SDLSupport.noLibrary) {
				/*
				The system failed to load the library. Usually this means that either the library or one of its dependencies could not be found.
				*/
			}
			else if(SDLSupport.badLibrary) {
				/*
				This indicates that the system was able to find and successfully load the library, but one or more symbols the binding expected to find was missing. This usually indicates that the loaded library is of a lower API version than the binding was configured to load, e.g., an SDL 2.0.2 library loaded by an SDL 2.0.10 configuration.

				For many C libraries, including SDL, this is perfectly fine and the application can continue as long as none of the missing functions are called.
				*/
			}
		}
		_sdl2 = new SDL2(_log);
		globalLogLevel = LogLevel.error;

		// You have to initialize each SDL subsystem you want by hand
		_sdl2.subSystemInit(SDL_INIT_VIDEO);
		_sdl2.subSystemInit(SDL_INIT_EVENTS);

		SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
		SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
		SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
		SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8);

		// create an OpenGL-enabled SDL window
		window = new SDL2Window(_sdl2,
								SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
								width, height,
								SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIDDEN );

		window.setTitle(title);

		GLSupport retVal = loadOpenGL();
		if(retVal >= GLSupport.gl33)
		{
			// configure renderer for OpenGL 3.3
			import std.stdio;
			writefln("Available version of opengl: %s", retVal);
		}
		else
		{
			import std.stdio;
			if (retVal == GLSupport.noLibrary)
				writeln("opengl is not available");
			else
				writefln("Unsupported version of opengl %s", retVal);
			import std.exception;
			enforce(0);
		}

		_gl = new OpenGL(_log);

		// redirect OpenGL output to our Logger
		_gl.redirectDebugOutput();

		_cursorSet[Cursor.Arrow]     = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_ARROW);
		_cursorSet[Cursor.IBeam]     = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_IBEAM);
		_cursorSet[Cursor.Crosshair] = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_CROSSHAIR);
		_cursorSet[Cursor.Hand]      = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_HAND);
		_cursorSet[Cursor.HResize]   = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_SIZEWE);
		_cursorSet[Cursor.VResize]   = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_SIZENS);
	}

	~this()
	{
		SDL_FreeCursor(_cursorSet[Cursor.Arrow]);
		SDL_FreeCursor(_cursorSet[Cursor.IBeam]);
		SDL_FreeCursor(_cursorSet[Cursor.Crosshair]);
		SDL_FreeCursor(_cursorSet[Cursor.Hand]);
		SDL_FreeCursor(_cursorSet[Cursor.HResize]);
		SDL_FreeCursor(_cursorSet[Cursor.VResize]);

		_gl.destroy();
		window.destroy();
		_sdl2.destroy();
	}

	private void delegate () _onBeforeLoopStart;
	void onBeforeLoopStart(void delegate () dg)
	{
		_onBeforeLoopStart = dg;
	}

	void run()
	{
		import gfm.sdl2;

		window.hide;
		SDL_FlushEvents(SDL_WINDOWEVENT, SDL_SYSWMEVENT);

		window.show;

		SDL_Event event;

		bool running = true;
		while (running)
		{
			if (_onBeforeLoopStart)
				_onBeforeLoopStart();

			SDL_PumpEvents();

			while (SDL_PeepEvents(&event, 1, SDL_GETEVENT, SDL_FIRSTEVENT, SDL_SYSWMEVENT))
			{
				switch (event.type)
				{
					case SDL_WINDOWEVENT:
					{
						switch (event.window.event)
						{
							case SDL_WINDOWEVENT_MOVED:
								// window has been moved to other position
								break;

							case SDL_WINDOWEVENT_RESIZED:
							case SDL_WINDOWEVENT_SIZE_CHANGED:
							{
								// window size has been resized
								with(event.window)
								{
									width = data1;
									height = data2;
								}
								break;
							}

							case SDL_WINDOWEVENT_SHOWN:
							case SDL_WINDOWEVENT_FOCUS_GAINED:
							case SDL_WINDOWEVENT_RESTORED:
							case SDL_WINDOWEVENT_MAXIMIZED:
								// window has been activated
								break;

							case SDL_WINDOWEVENT_HIDDEN:
							case SDL_WINDOWEVENT_FOCUS_LOST:
							case SDL_WINDOWEVENT_MINIMIZED:
								// window has been deactivated
								break;

							case SDL_WINDOWEVENT_ENTER:
								// mouse cursor has entered window
								// for example default cursor can be disable
								// using SDL_ShowCursor(SDL_FALSE);
								break;

							case SDL_WINDOWEVENT_LEAVE:
								// mouse cursor has left window
								// for example default cursor can be disable
								// using SDL_ShowCursor(SDL_TRUE);
								break;

							case SDL_WINDOWEVENT_CLOSE:
								running = false;
								break;
							default:
						}
						break;
					}
					default:
				}
			}

			// mouse update
			{
				while (SDL_PeepEvents(&event, 1, SDL_GETEVENT, SDL_MOUSEMOTION, SDL_MOUSEWHEEL))
				{
					switch (event.type)
					{
					case SDL_MOUSEBUTTONDOWN:
						onMouseDown(event);
						// force redrawing
						_needToDraw = true;
						break;
					case SDL_MOUSEBUTTONUP:
						onMouseUp(event);
						// force redrawing
						_needToDraw = true;
						break;
					case SDL_MOUSEMOTION:
						onMouseMotion(event);
						// force redrawing
						_needToDraw = true;
						break;
					case SDL_MOUSEWHEEL:
						onMouseWheel(event);
						// force redrawing
						_needToDraw = true;
						break;
					default:
					}
				}
			}

			// keyboard update
			{
				while (SDL_PeepEvents(&event, 1, SDL_GETEVENT, SDL_KEYDOWN, SDL_KEYUP))
				{
					switch (event.type)
					{
						case SDL_KEYDOWN:
							onKeyDown(event);
							// force redrawing
							_needToDraw = true;
							break;
						case SDL_KEYUP:
							onKeyUp(event);
							// force redrawing
							_needToDraw = true;
							break;
						default:
					}
				}
			}

			// text update
			{
				while (SDL_PeepEvents(&event, 1, SDL_GETEVENT, SDL_TEXTINPUT, SDL_TEXTINPUT))
				{
					switch (event.type)
					{
						case SDL_TEXTINPUT:
							import core.stdc.string : strlen;
							auto len = strlen(&event.text.text[0]);
							if (!len)
								break;
							assert(len < event.text.text.sizeof);
							auto txt = event.text.text[0..len];
							import std.utf : byDchar;

							// force redrawing
							_needToDraw = true;
							break;
						default:
							break;
					}
				}
			}

			// user event, we use it as timer notification
			{
				while (SDL_PeepEvents(&event, 1, SDL_GETEVENT, SDL_USEREVENT, SDL_USEREVENT))
				{
					switch (event.type)
					{
						case SDL_USEREVENT:
							// force redrawing
							_needToDraw = true;
							break;
						default:
							break;
					}
				}
			}

			// perform drawing if needed
			{
				import std.datetime : dur;

				static auto pauseTimeMs = 0;
				currTime = Clock.currTime.stdTime;
				if (currTime - mBlinkingCursorTimestamp > dur!"msecs"(500).total!"hnsecs")
				{
					mBlinkingCursorVisible = !mBlinkingCursorVisible;
					_needToDraw = true;
					mBlinkingCursorTimestamp = currTime;
				}

				if (_needToDraw)
				{
					pauseTimeMs = 0;

					window.swapBuffers();
				}
				else
				{
					pauseTimeMs = pauseTimeMs * 2 + 1; // exponential pause
					if (pauseTimeMs > 100)
						pauseTimeMs = 100; // max 100ms of pause
					SDL_Delay(pauseTimeMs);
				}
			}
		}
	}

	auto currTime() const { return _timestamp; }
	void currTime(long value)
	{
		_timestamp = value;
	}

	void cursor(Cursor value)
	{
		_cursor = value;
		SDL_SetCursor(_cursorSet[_cursor]);
	}

	Cursor cursor() const
	{
		return _cursor;
	}

	Logger logger() { return _log; }

protected:
	SDL2Window window;
	int width;
	int height;

	int modifiers;

	Logger _log;
	OpenGL _gl;
	SDL2 _sdl2;

	Cursor _cursor;

	bool _needToDraw;
	long _timestamp, _LastInteraction;

	// should the cursor be visible now
	bool mBlinkingCursorVisible;
	// the moment in time when the cursor has changed its blinking visibility
	long mBlinkingCursorTimestamp;

	SDL_Cursor*[6] _cursorSet;

	public void onKeyDown(ref const(SDL_Event) event)
	{
	}

	public void onKeyUp(ref const(SDL_Event) event)
	{
		
	}

	public void onMouseWheel(ref const(SDL_Event) event)
	{
	}
	
	public void onMouseMotion(ref const(SDL_Event) event)
	{
	}

	public void onMouseUp(ref const(SDL_Event) event)
	{
	}

	public void onMouseDown(ref const(SDL_Event) event)
	{
	}
}
