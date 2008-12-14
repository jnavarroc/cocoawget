/* DownloadItem */

#import <Cocoa/Cocoa.h>

#define DOWNLOADING NSLocalizedString(@"Downloading",@"")
#define CONNECTING NSLocalizedString(@"Connecting",@"")
#define FINISHED NSLocalizedString(@"Finished",@"")
#define WAITING NSLocalizedString(@"waiting",@"")
#define CANCELED NSLocalizedString(@"Canceled",@"")

#define DEBUG

#ifdef DEBUG
#define NSLOG NSLog
#else
#define NSLOG(fmt, ...) //(fmt)
#endif


@interface DownloadItem : NSObject
{
    NSMutableString *status;
    NSMutableString *percent;
    NSMutableString *speed;
	NSString *downloadedFilePath;
	
    NSImage  *icon;
    
    NSString *url;
    NSString *httpUser;
    NSString *httpPassword;
    NSString *referer;
    
    id resume;
    id checkTimeStamp;
    id recursive;
    id  recursiveType;
    id  recursiveLevel;

    
    //task
    NSTask *wgetTask;
    NSPipe *wgetPipe;
    
    NSMutableString *lastLogLine;
    NSMutableString *logString;

    id delegate;
}
/// return true if this item is downloading
-(BOOL)isDownloading;
/// return filename of item
-(NSString*)fileName;
/// icon file of this file. icon is specified by file extension
-(NSImage*)icon;
/// return all log
-(NSString*)logString;
/// return last line of log
-(NSString*)lastLogLine;

/// start downloadging
-(void)startDownload;
/// stop downloading
-(void)stopDownload;
/// if downloadin stop downloading, otherwise start downloading
-(void)startStop;


-(void)setDelegate:(id)aDelegate;

@end

@interface NSObject(DownloadItemDelegate)
-(void)logUpdated:(DownloadItem*)item;
-(void)downloadFinished:(DownloadItem*)item;
@end
