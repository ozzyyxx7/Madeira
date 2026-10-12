#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class DSCoreBridge;

@protocol DSCoreBridgeDelegate <NSObject>
- (void)dsCore:(DSCoreBridge *)core didRenderImage:(UIImage *)image;
@end

// One in-process libretro session. The signed core is bundled in Frameworks;
// ROMs, firmware and save data stay in the app's Documents directory.
@interface DSCoreBridge : NSObject
@property (nonatomic, weak, nullable) id<DSCoreBridgeDelegate> delegate;
@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, readonly) CGSize videoSize;
- (BOOL)startROMAtURL:(NSURL *)romURL
          systemURL:(NSURL *)systemURL
            saveURL:(NSURL *)saveURL
              error:(NSError * _Nullable * _Nullable)error;
- (void)setButton:(NSUInteger)button pressed:(BOOL)pressed;
- (void)setTouchX:(int16_t)x y:(int16_t)y pressed:(BOOL)pressed;
- (void)save;
- (void)setPaused:(BOOL)paused;
- (void)recordDiagnostic:(NSString *)message;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
