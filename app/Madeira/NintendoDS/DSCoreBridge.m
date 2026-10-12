#import "DSCoreBridge.h"
#import "libretro.h"
#import <AVFoundation/AVFoundation.h>
#import <GameController/GameController.h>
#import <stdatomic.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <stdarg.h>
#import <sys/mman.h>
#import <sys/stat.h>
#import <unistd.h>

static const NSUInteger DSAudioCapacity = 65536;
static __weak DSCoreBridge *activeCore;

typedef struct {
    void (*setEnvironment)(retro_environment_t);
    void (*setVideo)(retro_video_refresh_t);
    void (*setAudio)(retro_audio_sample_t);
    void (*setAudioBatch)(retro_audio_sample_batch_t);
    void (*setInputPoll)(retro_input_poll_t);
    void (*setInputState)(retro_input_state_t);
    void (*init)(void);
    void (*deinit)(void);
    bool (*loadGame)(const struct retro_game_info *);
    void (*unloadGame)(void);
    void (*run)(void);
    void (*getAVInfo)(struct retro_system_av_info *);
    void *(*getMemoryData)(unsigned);
    size_t (*getMemorySize)(unsigned);
    void (*setController)(unsigned, unsigned);
} DSFunctions;

@interface DSCoreBridge () {
@public
    void *_library;
    DSFunctions _core;
    void *_romBytes;
    size_t _romSize;
    BOOL _initialized;
    BOOL _loaded;
    BOOL _running;
    NSString *_romPath;
    NSString *_savePath;
    NSString *_systemPath;
    NSURL *_saveFile;
    CADisplayLink *_displayLink;
    AVAudioEngine *_audioEngine;
    AVAudioSourceNode *_audioSource;
    int16_t *_audioSamples;
    atomic_uint _audioRead;
    atomic_uint _audioWrite;
    uint32_t _buttons;
    int16_t _touchX;
    int16_t _touchY;
    BOOL _touchPressed;
    NSTimeInterval _lastSave;
    CFTimeInterval _lastFrameTime;
    CFTimeInterval _frameRemainder;
    double _frameInterval;
    CGSize _videoSize;
    FILE *_logFile;
    NSUInteger _runCalls;
    NSUInteger _videoFrames;
}
@end

static void DSRecord(const char *format, ...) {
    DSCoreBridge *bridge = activeCore;
    if (!bridge || !bridge->_logFile) return;
    va_list arguments;
    va_start(arguments, format);
    vfprintf(bridge->_logFile, format, arguments);
    va_end(arguments);
    fputc('\n', bridge->_logFile);
    fflush(bridge->_logFile);
}

static void DSCoreLog(enum retro_log_level level, const char *format, ...) {
    DSCoreBridge *bridge = activeCore;
    if (!bridge || !bridge->_logFile) return;
    fprintf(bridge->_logFile, "[core:%d] ", level);
    va_list arguments;
    va_start(arguments, format);
    vfprintf(bridge->_logFile, format, arguments);
    va_end(arguments);
    fflush(bridge->_logFile);
}

static BOOL DSEnvironment(unsigned command, void *data) {
    DSCoreBridge *bridge = activeCore;
    if (!bridge) return NO;
    switch (command) {
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
            *(const char **)data = bridge->_systemPath.UTF8String;
            return YES;
        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
            *(const char **)data = bridge->_savePath.UTF8String;
            return YES;
        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
            return *(enum retro_pixel_format *)data == RETRO_PIXEL_FORMAT_XRGB8888;
        case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
            return YES;
        case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
            *(bool *)data = false;
            return YES;
        case RETRO_ENVIRONMENT_GET_LANGUAGE:
            *(unsigned *)data = RETRO_LANGUAGE_ENGLISH;
            return YES;
        case RETRO_ENVIRONMENT_GET_CAN_DUPE:
            *(bool *)data = true;
            return YES;
        case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
            ((struct retro_log_callback *)data)->log = DSCoreLog;
            return YES;
        case RETRO_ENVIRONMENT_SET_MESSAGE:
            DSRecord("[message] %s", ((struct retro_message *)data)->msg);
            return NO;
        case RETRO_ENVIRONMENT_SET_MESSAGE_EXT:
            DSRecord("[message] %s", ((struct retro_message_ext *)data)->msg);
            return NO;
        case RETRO_ENVIRONMENT_SHUTDOWN:
            DSRecord("[core] requested shutdown");
            return YES;
        default:
            return NO; // Optional interfaces fall back to the core's defaults.
    }
}

static void DSVideo(const void *pixels, unsigned width, unsigned height, size_t pitch) {
    DSCoreBridge *bridge = activeCore;
    if (!bridge || !pixels || !width || !height) return;
    NSData *frame = [NSData dataWithBytes:pixels length:pitch * height];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)frame);
    CGColorSpaceRef colors = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo format = kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst;
    CGImageRef image = CGImageCreate(width, height, 8, 32, pitch, colors, format,
                                    provider, NULL, false, kCGRenderingIntentDefault);
    if (image) {
        bridge->_videoFrames++;
        if (bridge->_videoFrames <= 3 || bridge->_videoFrames % 120 == 0) {
            DSRecord("[video] frame=%lu size=%ux%u pitch=%zu firstpixel=%08x",
                     (unsigned long)bridge->_videoFrames, width, height, pitch,
                     *(const uint32_t *)pixels);
        }
        bridge->_videoSize = CGSizeMake(width, height);
        [bridge.delegate dsCore:bridge didRenderImage:[UIImage imageWithCGImage:image]];
        CGImageRelease(image);
    }
    CGColorSpaceRelease(colors);
    CGDataProviderRelease(provider);
}

static size_t DSAudioBatch(const int16_t *samples, size_t frames) {
    DSCoreBridge *bridge = activeCore;
    if (!bridge || !bridge->_audioSamples) return frames;
    unsigned write = atomic_load_explicit(&bridge->_audioWrite, memory_order_relaxed);
    unsigned read = atomic_load_explicit(&bridge->_audioRead, memory_order_acquire);
    for (size_t i = 0; i < frames; i++) {
        if (write - read >= DSAudioCapacity) break;
        unsigned index = (write % DSAudioCapacity) * 2;
        bridge->_audioSamples[index] = samples[i * 2];
        bridge->_audioSamples[index + 1] = samples[i * 2 + 1];
        write++;
    }
    atomic_store_explicit(&bridge->_audioWrite, write, memory_order_release);
    return frames;
}

static void DSAudioSample(int16_t left, int16_t right) {
    int16_t pair[] = { left, right };
    DSAudioBatch(pair, 1);
}

static void DSInputPoll(void) {}

static uint32_t DSControllerButtons(void) {
    GCController *controller = GCController.controllers.firstObject;
    GCExtendedGamepad *pad = controller.extendedGamepad;
    if (!pad) return 0;
    uint32_t bits = 0;
#define DS_PAD(key, id) if (pad.key.isPressed) bits |= (1u << id)
    DS_PAD(buttonA, RETRO_DEVICE_ID_JOYPAD_A);
    DS_PAD(buttonB, RETRO_DEVICE_ID_JOYPAD_B);
    DS_PAD(buttonX, RETRO_DEVICE_ID_JOYPAD_X);
    DS_PAD(buttonY, RETRO_DEVICE_ID_JOYPAD_Y);
    DS_PAD(leftShoulder, RETRO_DEVICE_ID_JOYPAD_L);
    DS_PAD(rightShoulder, RETRO_DEVICE_ID_JOYPAD_R);
    DS_PAD(buttonMenu, RETRO_DEVICE_ID_JOYPAD_START);
    DS_PAD(buttonOptions, RETRO_DEVICE_ID_JOYPAD_SELECT);
    DS_PAD(dpad.up, RETRO_DEVICE_ID_JOYPAD_UP);
    DS_PAD(dpad.down, RETRO_DEVICE_ID_JOYPAD_DOWN);
    DS_PAD(dpad.left, RETRO_DEVICE_ID_JOYPAD_LEFT);
    DS_PAD(dpad.right, RETRO_DEVICE_ID_JOYPAD_RIGHT);
#undef DS_PAD
    return bits;
}

static int16_t DSInputState(unsigned port, unsigned device, unsigned index, unsigned id) {
    DSCoreBridge *bridge = activeCore;
    if (!bridge || port != 0 || index != 0) return 0;
    if (device == RETRO_DEVICE_JOYPAD) {
        uint32_t buttons = bridge->_buttons | DSControllerButtons();
        if (id == RETRO_DEVICE_ID_JOYPAD_MASK) return (int16_t)buttons;
        return id < 16 && (buttons & (1u << id)) ? 1 : 0;
    }
    if (device == RETRO_DEVICE_POINTER) {
        if (id == RETRO_DEVICE_ID_POINTER_X) return bridge->_touchX;
        if (id == RETRO_DEVICE_ID_POINTER_Y) return bridge->_touchY;
        if (id == RETRO_DEVICE_ID_POINTER_PRESSED) return bridge->_touchPressed ? 1 : 0;
    }
    return 0;
}

@implementation DSCoreBridge

- (BOOL)isRunning { return _running; }
- (CGSize)videoSize { return _videoSize; }

- (BOOL)startROMAtURL:(NSURL *)romURL systemURL:(NSURL *)systemURL
            saveURL:(NSURL *)saveURL error:(NSError **)error {
    [self stop];
    NSError *fileError = nil;
    [[NSFileManager defaultManager] createDirectoryAtURL:systemURL withIntermediateDirectories:YES attributes:nil error:&fileError];
    if (!fileError) [[NSFileManager defaultManager] createDirectoryAtURL:saveURL withIntermediateDirectories:YES attributes:nil error:&fileError];
    if (fileError) { if (error) *error = fileError; return NO; }

    NSURL *logDir = [[systemURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"Logs" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:logDir withIntermediateDirectories:YES attributes:nil error:nil];
    _logFile = fopen([[logDir URLByAppendingPathComponent:@"core.log"] path].fileSystemRepresentation, "w");
    activeCore = self;
    DSRecord("[host] start, rom_bytes pending");

    NSString *libraryPath = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"melondsds_libretro.dylib"];
    _library = dlopen(libraryPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!_library) {
        [self failWithMessage:[NSString stringWithFormat:@"melonDS DS core could not load: %s", dlerror() ?: "unknown error"] error:error];
        return NO;
    }
    DSRecord("[host] dlopen complete");
#define DS_SYMBOL(field, symbol) _core.field = dlsym(_library, "retro_" #symbol); if (!_core.field) { [self failWithMessage:@"melonDS DS core is missing required libretro functions." error:error]; return NO; }
    DS_SYMBOL(setEnvironment, set_environment);
    DS_SYMBOL(setVideo, set_video_refresh);
    DS_SYMBOL(setAudio, set_audio_sample);
    DS_SYMBOL(setAudioBatch, set_audio_sample_batch);
    DS_SYMBOL(setInputPoll, set_input_poll);
    DS_SYMBOL(setInputState, set_input_state);
    DS_SYMBOL(init, init);
    DS_SYMBOL(deinit, deinit);
    DS_SYMBOL(loadGame, load_game);
    DS_SYMBOL(unloadGame, unload_game);
    DS_SYMBOL(run, run);
    DS_SYMBOL(getAVInfo, get_system_av_info);
    DS_SYMBOL(getMemoryData, get_memory_data);
    DS_SYMBOL(getMemorySize, get_memory_size);
    DS_SYMBOL(setController, set_controller_port_device);
#undef DS_SYMBOL

    int fd = open(romURL.path.fileSystemRepresentation, O_RDONLY);
    struct stat statbuf;
    if (fd < 0 || fstat(fd, &statbuf) != 0 || statbuf.st_size < 512 || statbuf.st_size > (1LL << 30)) {
        if (fd >= 0) close(fd);
        [self failWithMessage:@"The DS ROM could not be read or is larger than 1 GB." error:error];
        return NO;
    }
    _romSize = (size_t)statbuf.st_size;
    DSRecord("[host] ROM size=%zu", _romSize);
    _romBytes = mmap(NULL, _romSize, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (_romBytes == MAP_FAILED) {
        _romBytes = NULL;
        [self failWithMessage:@"The DS ROM could not be mapped into memory." error:error];
        return NO;
    }

    _romPath = romURL.path;
    _systemPath = systemURL.path;
    _savePath = saveURL.path;
    _saveFile = [[saveURL URLByAppendingPathComponent:romURL.lastPathComponent] URLByDeletingPathExtension];
    _saveFile = [_saveFile URLByAppendingPathExtension:@"srm"];
    _core.setEnvironment(DSEnvironment);
    _core.setVideo(DSVideo);
    _core.setAudio(DSAudioSample);
    _core.setAudioBatch(DSAudioBatch);
    _core.setInputPoll(DSInputPoll);
    _core.setInputState(DSInputState);
    _core.init();
    _initialized = YES;
    DSRecord("[host] retro_init complete");
    _core.setController(0, RETRO_DEVICE_JOYPAD);
    struct retro_game_info game = { _romPath.fileSystemRepresentation, _romBytes, _romSize, NULL };
    if (!_core.loadGame(&game)) {
        [self failWithMessage:@"melonDS DS could not open this ROM. Check the file and any required firmware." error:error];
        return NO;
    }
    _loaded = YES;
    DSRecord("[host] retro_load_game complete");
    void *sram = _core.getMemoryData(RETRO_MEMORY_SAVE_RAM);
    size_t sramSize = _core.getMemorySize(RETRO_MEMORY_SAVE_RAM);
    NSData *saved = [NSData dataWithContentsOfURL:_saveFile];
    if (sram && sramSize && saved.length) memcpy(sram, saved.bytes, MIN(sramSize, saved.length));

    struct retro_system_av_info av = {0};
    _core.getAVInfo(&av);
    DSRecord("[host] av width=%u height=%u fps=%.3f audio=%.1f", av.geometry.base_width,
             av.geometry.base_height, av.timing.fps, av.timing.sample_rate);
    _videoSize = CGSizeMake(av.geometry.base_width, av.geometry.base_height);
    _frameInterval = av.timing.fps > 0 ? 1.0 / av.timing.fps : 1.0 / 60.0;
    _lastFrameTime = 0;
    _frameRemainder = 0;
    [self startAudioAtSampleRate:av.timing.sample_rate];
    _running = YES;
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(nextFrame:)];
    _displayLink.preferredFramesPerSecond = av.timing.fps > 0 ? (NSInteger)round(av.timing.fps) : 60;
    [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    DSRecord("[host] display link started");
    return YES;
}

- (void)startAudioAtSampleRate:(double)sampleRate {
    if (sampleRate < 8000 || sampleRate > 192000) return;
    _audioSamples = calloc(DSAudioCapacity * 2, sizeof(int16_t));
    atomic_init(&_audioRead, 0);
    atomic_init(&_audioWrite, 0);
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:2];
    __weak DSCoreBridge *weakSelf = self;
    _audioSource = [[AVAudioSourceNode alloc] initWithFormat:format renderBlock:^OSStatus(BOOL *isSilence, const AudioTimeStamp *timestamp, AVAudioFrameCount frameCount, AudioBufferList *outputData) {
        DSCoreBridge *bridge = weakSelf;
        float *left = outputData->mBuffers[0].mData;
        float *right = outputData->mBuffers[1].mData;
        unsigned read = bridge ? atomic_load_explicit(&bridge->_audioRead, memory_order_relaxed) : 0;
        unsigned write = bridge ? atomic_load_explicit(&bridge->_audioWrite, memory_order_acquire) : 0;
        for (AVAudioFrameCount i = 0; i < frameCount; i++) {
            if (bridge && read < write) {
                unsigned index = (read % DSAudioCapacity) * 2;
                left[i] = bridge->_audioSamples[index] / 32768.0f;
                right[i] = bridge->_audioSamples[index + 1] / 32768.0f;
                read++;
            } else {
                left[i] = right[i] = 0;
            }
        }
        if (bridge) atomic_store_explicit(&bridge->_audioRead, read, memory_order_release);
        if (isSilence) *isSilence = read == write;
        return noErr;
    }];
    _audioEngine = [AVAudioEngine new];
    [_audioEngine attachNode:_audioSource];
    [_audioEngine connect:_audioSource to:_audioEngine.mainMixerNode format:format];
    NSError *audioError = nil;
    if (![_audioEngine startAndReturnError:&audioError]) NSLog(@"[Nintendo DS] Audio unavailable: %@", audioError);
}

- (void)nextFrame:(CADisplayLink *)link {
    if (!_running) return;
    if (_lastFrameTime == 0) {
        DSRecord("[host] first retro_run begin");
        _core.run();
        DSRecord("[host] first retro_run end");
        _runCalls++;
    } else {
        _frameRemainder += MIN(link.timestamp - _lastFrameTime, 0.1);
        // A 60 Hz display and the DS's ~59.8 Hz clock are not identical.
        // Occasionally skip a display tick instead of building audio latency.
        for (int i = 0; i < 2 && _frameRemainder >= _frameInterval; i++) {
            if (_runCalls == 1) DSRecord("[host] second retro_run begin");
            _core.run();
            _runCalls++;
            if (_runCalls == 2) DSRecord("[host] second retro_run end");
            if (_runCalls % 120 == 0) DSRecord("[host] run=%lu video=%lu", (unsigned long)_runCalls, (unsigned long)_videoFrames);
            _frameRemainder -= _frameInterval;
        }
    }
    _lastFrameTime = link.timestamp;
    if (link.timestamp - _lastSave >= 5.0) {
        [self save];
        _lastSave = link.timestamp;
    }
}

- (void)setButton:(NSUInteger)button pressed:(BOOL)pressed {
    if (button >= 16) return;
    if (pressed) _buttons |= 1u << button;
    else _buttons &= ~(1u << button);
}

- (void)setTouchX:(int16_t)x y:(int16_t)y pressed:(BOOL)pressed {
    _touchX = x;
    _touchY = y;
    _touchPressed = pressed;
}

- (void)save {
    if (!_loaded) return;
    void *sram = _core.getMemoryData(RETRO_MEMORY_SAVE_RAM);
    size_t size = _core.getMemorySize(RETRO_MEMORY_SAVE_RAM);
    if (sram && size) [[NSData dataWithBytes:sram length:size] writeToURL:_saveFile options:NSDataWritingAtomic error:nil];
}

- (void)setPaused:(BOOL)paused {
    _displayLink.paused = paused;
    if (paused) {
        [self save];
        [_audioEngine pause];
    } else {
        _lastFrameTime = 0;
        [_audioEngine startAndReturnError:nil];
    }
}

- (void)recordDiagnostic:(NSString *)message {
    DSRecord("[ui] %s", message.UTF8String);
}

- (void)stop {
    DSRecord("[host] stop run=%lu video=%lu", (unsigned long)_runCalls, (unsigned long)_videoFrames);
    [_displayLink invalidate]; _displayLink = nil;
    _running = NO;
    [_audioEngine stop]; _audioEngine = nil; _audioSource = nil;
    [self save];
    if (_loaded) { _core.unloadGame(); _loaded = NO; }
    if (_initialized) { _core.deinit(); _initialized = NO; }
    if (_library) { dlclose(_library); _library = NULL; }
    if (_romBytes) { munmap(_romBytes, _romSize); _romBytes = NULL; }
    if (activeCore == self) activeCore = nil;
    if (_logFile) { fclose(_logFile); _logFile = NULL; }
    free(_audioSamples); _audioSamples = NULL;
    memset(&_core, 0, sizeof(_core));
    _buttons = 0; _touchPressed = NO;
    _lastFrameTime = 0; _frameRemainder = 0;
    _runCalls = 0; _videoFrames = 0;
}

- (void)failWithMessage:(NSString *)message error:(NSError **)error {
    if (error) *error = [NSError errorWithDomain:@"MadeiraNintendoDS" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
    [self stop];
}

- (void)dealloc { [self stop]; }
@end
