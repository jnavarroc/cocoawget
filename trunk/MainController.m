#import "MainController.h"
#import "CWArrayController.h"

@implementation MainController

- (IBAction)showHelp:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://cocoawget.nobody.jp/help/"]];
}
- (IBAction)showWgetOptionHelp:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://cocoawget.nobody.jp/help/WgetHelp.html"]];
}
-(void)setDirectorySheetEnd:(NSOpenPanel*)sheet
                            returnCode:(int) returnCode
                            contextInfo:(void*)contextInfo
{
    if(returnCode==NSOKButton){
        NSString *downloadFolder=[[sheet filename] copy];
        [[[NSUserDefaultsController sharedUserDefaultsController] values] setValue:downloadFolder forKey:@"downloadFolder"];
    }                           
}



- (IBAction)selectDownloadFolder:(id)sender
{
    NSOpenPanel *dialog;
    NSString *defaultDirectory;
    dialog=[NSOpenPanel openPanel];
    [dialog setCanChooseDirectories:YES];
    [dialog setCanChooseFiles:NO];
    
    NSString *downloadFolder=[[[NSUserDefaultsController sharedUserDefaultsController] values] valueForKey:@"downloadFolder"];
    
    if(downloadFolder) defaultDirectory=downloadFolder;
    else defaultDirectory=[NSString stringWithFormat:@"%@",NSHomeDirectory()];
    [dialog beginSheetForDirectory:defaultDirectory
    file:nil types:nil modalForWindow:prefWindow modalDelegate:self 
    didEndSelector: @selector(setDirectorySheetEnd:returnCode:contextInfo:)
    contextInfo:nil];
}


-(BOOL)confirmClose
{
    
    NSAlert *alert = [ NSAlert alertWithMessageText: 
        NSLocalizedString(@"Are you sure to quit application?",@"")  
        defaultButton: NSLocalizedString(@"Yes",@"")  
        alternateButton: NSLocalizedString(@"No",@"") 
        otherButton: nil
        informativeTextWithFormat: 
        NSLocalizedString(@"Downloading item exists.",@"") ];
    
    //[ alert setShowsHelp: YES ];
    //[ alert setAlertStyle: NSCriticalAlertStyle ];
    //[ alert setDelegate: self ];
    
    //[ alert beginSheetModalForWindow:mainWindow modalDelegate:self didEndSelector:@selector(deleteConfirmSheedDidEnd: returnCode: contextInfo:) contextInfo:nil ];
    int result = [ alert runModal ];
    if(result==NSAlertDefaultReturn) return YES;
    else return NO;

}

- (BOOL)canCloseWindow
{
    if([(CWArrayController*)arrayController downloadingCount]==0) return YES;
    else return [self confirmClose];
}

-(void)applicationWillTerminate:(NSNotification*) notification
{
    //NSLog(@"applicationWillTerminate");
    [(CWArrayController*)arrayController clear];
}


- (BOOL)windowShouldClose:(id)sender
{
    //NSLog(@"windowShouldClose");
    return [self canCloseWindow];
}
- (void)windowWillClose:(NSNotification *)aNotification
{
    //NSLog(@"windowWillClose");
    [mainWindow setDelegate:nil];
    [NSApp terminate:self];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app 
{
    //NSLog(@"applicationShouldTerminate");
    if([self canCloseWindow])
        return NSTerminateNow;
    else
        return NSTerminateCancel; 
}

- (void)applicationDidBecomeActive/*windowDidBecomeKey*/:(NSNotification *)aNotification
{
    [mainWindow makeFirstResponder:url];    
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
	if(!filename) return NO;
	NSLog(@"application openfile");
    NSLog(filename);
	NSMutableString *filePath=[NSMutableString stringWithCapacity:0];
	[filePath setString:filename];
	[filePath replaceOccurrencesOfString:@"/:" withString:@"/" options:NSLiteralSearch range:NSMakeRange(0, [filePath length])];
	[filePath replaceOccurrencesOfString:@":" withString:@"/" options:NSLiteralSearch range:NSMakeRange(0, [filePath length])];
	NSError *error;
    NSString *contents = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:&error]; 
	NSLog(filePath);
	NSLog(contents);
	if(!contents) return NO;
    
	return YES;
}
@end
