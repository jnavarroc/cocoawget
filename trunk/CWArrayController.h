/* CWArrayController */

#import <Cocoa/Cocoa.h>
						
@class DownloadItem;
@interface CWArrayController : NSArrayController
{
    IBOutlet id urlTextField;
    IBOutlet id tableView;
    IBOutlet id startButton;
    
    IBOutlet id logView;
    IBOutlet id drawer;
    
    int draggingIndex;
    
    NSTimer		*timer;
    BOOL isChecking;
    
    NSAppleScript* appleScript;
    
}
- (IBAction)addToList:(id)sender;
- (IBAction)delete:(id)sender;

- (IBAction)startStop:(id)sender;

- (IBAction)setURL:(id)sender;
- (IBAction)setHTTPUser:(id)sender;
- (IBAction)setHTTPPassword:(id)sender;
- (IBAction)setReferer:(id)sender;

- (IBAction)setResume:(id)sender;
- (IBAction)setCheckTimeStamp:(id)sender;
- (IBAction)setRecursive:(id)sender;
- (IBAction)setRecursiveType:(id)sender;
- (IBAction)setRecursiveLevel:(id)sender;
- (IBAction)setAutoDownload:(id)sender;

- (IBAction)showLog:(id)sender;

-(void)clear;
-(NSArray*)parseURL:(NSString*)str;

-(BOOL)isURLInList:(NSString *)urlString;

-(void)addURL:(NSString *)urlString;
-(void)addURLWithOutChecking:(NSString *)urlString;
-(void)insertURL:(NSString *)urlString atArrangedObjectIndex:(unsigned int)index;

-(DownloadItem *)downloadItem:(NSString *)urlString;

-(void)copyUserDefaultToSelectedDataForKey:(NSString*)key;
-(void)copyValueForKey:(NSString*)key from:(id)srcObj to:(id)dstObj;
-(void)createUserDefaults;

-(void)writeComment:(NSString*) comment toFile:(NSString*)filePath;

-(void)loadList;
-(void)saveList;

-(void)startTimer;
-(void)stopTimer;
-(BOOL)isTimerRunning;

-(void)stopAll;
-(void)updateDownloadInfo;

-(NSString*)domain:(NSString*)url;

-(void)downloadFinished:(DownloadItem*)item;
-(BOOL)downloadShouldStart:(DownloadItem*)data;
-(int)downloadingCount;
-(int)downloadingCountInDomain:(NSString*)domain;
-(void)removeFinishedDownload;

-(BOOL)isSarariRunning;
-(void)getRefererFromSafari;
@end
