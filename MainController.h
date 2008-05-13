/* MainController */

#import <Cocoa/Cocoa.h>

@interface MainController : NSObject
{
    IBOutlet id url;
    IBOutlet id mainWindow;
    IBOutlet id prefWindow;
    IBOutlet id arrayController;
}
- (IBAction)selectDownloadFolder:(id)sender;
- (IBAction)showWgetOptionHelp:(id)sender;
@end
