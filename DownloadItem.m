#import "DownloadItem.h"

@interface DownloadItem (Private)
    -(void)startWgetTask;
    -(void)stopWgetTask;
    -(NSString*)wgetPath;
    -(NSArray*)getArgument;
    -(void)backupWgetrc;
    -(void)updateWgetrc;
    -(void)restoreWgetrc;
    -(void)removeFromNotificationCenter;
    -(void)finish;
    -(void)parseLog:(NSString*)str;
    -(void)log:(NSString*)str;
    -(void)parseSavedFilePath;
@end

@implementation DownloadItem

+ (void)initialize {
    //NSLOG(@"DownloadItem::initialize");
    [DownloadItem setKeys:
        [NSArray arrayWithObjects:@"url", nil]
        triggerChangeNotificationsForDependentKey:@"fileName"];
    [DownloadItem setKeys:
        [NSArray arrayWithObjects:@"url", nil]
        triggerChangeNotificationsForDependentKey:@"icon"];
}
-(id)init
{
    NSLOG(@"DownloadItem::init");
    self=[super init];
    url=[[NSString alloc]initWithFormat:@""];
    
    status=[[NSMutableString alloc]initWithCapacity:32];
    [status setString:WAITING];
    percent=[[NSMutableString alloc]initWithCapacity:4];
    speed=[[NSMutableString alloc]initWithCapacity:16];
    
    
    referer=[[NSString alloc]initWithFormat:@""];
    httpUser=[[NSString alloc]initWithFormat:@""];
    httpPassword=[[NSString alloc]initWithFormat:@""];
    lastLogLine=[[NSMutableString alloc]initWithCapacity:32];
    logString=[[NSMutableString alloc]initWithCapacity:1024];
    
    return self;
}

-(void)dealloc
{
    NSLOG(@"DownloadItem::dealloc");
    if([self isDownloading]) [self stopDownload];
    [self removeFromNotificationCenter];
    [percent release];
    [logString release];
    [lastLogLine release];
    [httpPassword release];
    [httpUser release];
    [referer release];
    [status release];
    [speed release];
    [url release];
    
	[downloadedFilePath release];
	
    [super dealloc];
    NSLOG(@"DownloadItem::dealloc end");    
}

-(NSString*)fileName
{
    //NSLOG(@"DownloadItem::fileName");
    if(url){
        return [url lastPathComponent];
    }else return nil;
}

-(NSString*)logString
{
    return logString;
}

-(NSString*)lastLogLine
{
    return lastLogLine;
}

-(BOOL)isDownloading
{
    if(self && wgetTask) return [wgetTask isRunning];
    else return NO;
}


-(NSImage*)icon
{
    //NSLOG(@"DownloadItem::icon");

    if(!url) return nil;
    NSString* extension=[url pathExtension];
    if(!extension) return nil;
    return [[NSWorkspace sharedWorkspace]iconForFileType:extension];
}



-(void)startStop
{
    NSLOG(@"DownloadItem::startStop");
    if([self isDownloading]) {
        [status setString:CANCELED];
        [self setValue:status forKey:@"status"];
        [self stopDownload];
        
    }
    else [self startDownload];
}


-(void)startDownload
{
    NSLOG(@"DownloadItem::startDownload");
    if(![self isDownloading]) [self startWgetTask];
}

-(void)stopDownload
{
    NSLOG(@"DownloadItem::stopDownload");
    if([self isDownloading]) [self stopWgetTask];
}

-(void)finish
{
    NSLOG(@"DownloadItem::finish  %@",status);
    
    

    if([status isEqualToString:FINISHED]){
        return;
    }
    
    [self restoreWgetrc];
    
    if([status hasPrefix:@"Error"]==NO){
        [status setString:FINISHED];
        [self setValue:status forKey:@"status"];
        
        //20050423 set 100%
        [self setValue:@"100" forKey:@"percent"];

		//20050605 parse savedFilePath
		[self parseSavedFilePath];
    }
    
    
    if(delegate && [delegate respondsToSelector:@selector(downloadFinished:)]){
        [delegate downloadFinished:self];
    }

}

-(void)setDelegate:(id)aDelegate
{
    delegate=aDelegate;
}

-(void) initLogString:(NSString *)wgetPathString :(NSArray*)arguments
{
    [logString setString:@""];
    [logString appendString:wgetPathString];
    [logString appendString:@" "];
    int i=0;
    for(i=0;i<[arguments count];i++){
        [logString appendString:[arguments objectAtIndex:i]];
        [logString appendString:@" "];
    }
    [logString appendString:@"\n"];
}

-(void)startWgetTask
{
   
    NSString *wgetPathString;
    NSArray  *arguments;
    
    wgetTask=[[NSTask alloc] init];
    wgetPipe=[[NSPipe alloc] init];

    NSLOG(@"DownloadItem::startWgetTask");
    wgetPathString=[self wgetPath];
    [wgetTask setLaunchPath:wgetPathString];


    [wgetTask setStandardOutput:wgetPipe];// redirect stdout
    [wgetTask setStandardError:wgetPipe]; // redirect stderr
    
    //set arguments
    arguments=[self getArgument];    
    [wgetTask setArguments:arguments];

    [self initLogString: wgetPathString :arguments];
    
    //set callback function of reading stdour/err
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                        selector:@selector(readPipe:)
                                        name:NSFileHandleReadCompletionNotification
                                        object:[wgetPipe fileHandleForReading]];
                                        
    //set callback function of finishing wget process
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                        selector:@selector(terminateTask:)
                                        name:NSTaskDidTerminateNotification
                                        object:wgetTask];
                                                                           
    [[wgetPipe fileHandleForReading] readInBackgroundAndNotify];
    
    [self backupWgetrc];
    [self updateWgetrc];
    

    [status setString:CONNECTING];
    [self setValue:status forKey:@"status"];
            
    // run !!!
    [wgetTask launch];

    
    
}

-(void)stopWgetTask
{
    NSLOG(@"DownloadItem::stopWgetTask");
    
    [self restoreWgetrc];
    
    [wgetTask terminate];
    [self removeFromNotificationCenter];
    [wgetTask release];
    [wgetPipe release];
    wgetTask=nil;
    wgetPipe=nil;
}

-(NSString *) wgetPath
{
    //NSString *path = [NSString stringWithFormat:@"%@/Contents/Resources/wget",[[NSBundle mainBundle]bundlePath]];
    NSString *path = [[[NSBundle mainBundle]resourcePath]
    stringByAppendingPathComponent : @"wget" ];
    return path;
}

-(void)parseSavedFilePath
{
	if(!logString) return;
	NSLOG(@"DownloadItem::parseSavedFilePath");
	//NSLOG(logString);
	
	NSRange range=[logString rangeOfString:@"\' saved [" options:NSLiteralSearch|NSBackwardsSearch];
	NSLOG(@"range %d %d",range.location,range.length);
	if(range.length==0) return;
	NSRange range2=NSMakeRange(0,range.location-1);
	NSLOG(@"range2 %d %d",range2.location,range2.length);
	NSRange range3=[logString rangeOfString:@"\'" options:NSLiteralSearch|NSBackwardsSearch range:range2];
	NSLOG(@"range3 %d %d",range3.location,range3.length);
	if(range3.length==0) return;
	
	NSRange range4=NSMakeRange(range3.location+1,range.location-range3.location-1);
	NSLOG(@"range4 %d %d",range4.location,range4.length);
	NSString *s=[logString substringWithRange:range4];
	NSLOG(s);
	
	if(s){
	[downloadedFilePath release];
	downloadedFilePath=s;
	[downloadedFilePath retain];
	}
}

-(BOOL)parseDownloadedPath:(NSString*)str
{
    if([status isEqualToString:CONNECTING]==NO) return NO;

    int length=[str length];
    if(length<4) return NO;
	

	NSRange range=[str rangeOfString:@"=>" options:NSLiteralSearch];
	if(range.length==0) return NO;
	//NSLOG(@"range %d %d",range.location,range.length);
	
	NSString *str2=[str substringFromIndex:range.location+4];
	/*
	NSLOG(@"#########");
	NSLOG(str2);
	NSLOG(@"######### end");
	*/
	NSRange range2=[str2 rangeOfString:@"\'" options:NSLiteralSearch];
	if(range2.length<=0) return NO;
	
	//NSLOG(@"range2 %d %d",range2.location,range2.length);
	
	NSString *s=[str2 substringToIndex:range2.location];
	
	NSLOG(s);
	
	[downloadedFilePath release];
	downloadedFilePath=s;
	[downloadedFilePath retain];
	
	return NO;
}

-(BOOL)parseDownloadingProgress:(NSString*)str
{
/*
    if([status isEqualToString:DOWNLOADING]==NO &&
        [status isEqualToString:FINISHED]==NO ){
		if([str rangeOfString:@"200 OK" options:NSLiteralSearch].location>0){
            //if((strstr(cStr,"200 OK")!=NULL)){
			[status setString:DOWNLOADING];
			[self setValue:status forKey:@"status"];
		}else{
			//NSLog(@"------------------");
			//NSLog(str);
		}
    }	
*/
	if([status isEqualToString:DOWNLOADING]==NO &&
        [status isEqualToString:FINISHED]==NO ){
		[status setString:DOWNLOADING];
		[self setValue:status forKey:@"status"];
	}
    
    NSArray *array = [str componentsSeparatedByString:@" "];
    if(array==NULL) return NO;
    int n=[array count];
    //NSLOG(@"array count %d",n);
    if(n<=1) return NO;
    
    int startIndex=1;
    BOOL parseBPS=YES;
    for(int i=n-1;i>=startIndex;i--){
        NSString *s=[array objectAtIndex:i];
        int length=[s length];
        //NSLOG(@"==%d:<%@>",i,s);
        if(parseBPS){
            if( length>=1 && [s characterAtIndex :length-1] == 's'){
                //set speed
                NSString *speedStr=[[array objectAtIndex:i-1] stringByAppendingString:@"B/s"];
                if(speedStr) [self setValue:speedStr forKey:@"speed"];
                i--;
                parseBPS=NO;
            }
        }else{
            if(length>1){
                NSRange percentRange=[s rangeOfString:@"%" options:NSLiteralSearch];
                if(percentRange.length>0){
                    //set percent
                    NSString *percentString=[s substringToIndex:percentRange.location];
                    [self setValue:percentString forKey:@"percent"];
                    return YES;
                }
            }
        } 
    }
    return NO;
}
-(void)parseLog:(NSString*)str
{
/*
    NSLOG(@"parseLog ");
    NSLOG(str);
    NSLOG(@"parseLog end");
 */       
    BOOL result=NO;
    result=[self parseDownloadedPath:str];
    result=[self parseDownloadingProgress:str];
    if(result) return;
    if(
        ([str rangeOfString:@"ERROR"  options:NSLiteralSearch].length>0) 
        ){
        [status setString:[NSString stringWithFormat:@"Error: %@",str]];
        [self setValue:status forKey:@"status"];
    }else{
       //NSLOG(str); 
    }
}

-(void)log:(NSString*)str
{
    //NSLOG(str);
    if(str==nil) return;
    if([str length]==0) return;

NS_DURING
        
        //add to log
        [logString appendString:str];        
        [lastLogLine appendString:str];

        NSUInteger lastLogLineLength=[lastLogLine length];
        if(lastLogLineLength<10) return;
        NSRange range=NSMakeRange(0, lastLogLineLength);
        range = [lastLogLine lineRangeForRange:NSMakeRange(range.location, 0)];
        //NSLOG(@"%d %d %d",lastLogLineLength,range.length,range.location);
        if(range.length>0){
            NSString *line=[lastLogLine substringWithRange:range];
            [self parseLog:line];            
            //notify logUpdate
            if(self && delegate && [delegate respondsToSelector:@selector(logUpdated:)]){
                [delegate logUpdated:self];
            }
        
            if(self) [lastLogLine deleteCharactersInRange:range];
        }

NS_HANDLER
    // deal with any exception
    //NSLog(@"exception");
	//if(str) NSLog(str);
NS_ENDHANDLER
}

-(void)readPipe:(NSNotification *)notification
{
    NSData *data=[[notification userInfo] objectForKey:NSFileHandleNotificationDataItem];
    if(!data) return;
    if([data length]){
        NSString *str=[[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding] autorelease];
        [self log:str];
        //20050420
        if(self){
            if([status isEqualToString:DOWNLOADING]){
                double sleepTime=0.2;//0.1
                [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:sleepTime]];
            }
        }
		    
        if(self)[[wgetPipe fileHandleForReading] readInBackgroundAndNotify];
    }
    else {
        NSLOG(@"DownloadItem::readPipe length=0");
        
        //20050423
        [self log:@""];
        
            /*    
        [self stopDownload];
        [self finish];
        */
    }
}

-(void)terminateTask:(NSNotification *)notification
{
    int terminationStatus=[[notification object] terminationStatus];
    NSLOG(@"DownloadItem::terminateTask");
    
    BOOL finished=NO;
    if(terminationStatus!=0){
        
        [status setString:[NSString stringWithFormat:@"Error: Task failed:%d",terminationStatus]];
        [self setValue:status forKey:@"status"];
    }else{
        if([status isEqualToString:CONNECTING]){
            [status setString:@"Error"];
            [self setValue:status forKey:@"status"];
        }else{
            //downloading
            finished=YES;
        }
    }
    [self stopDownload];
    if(finished) [self finish];
	
    NSLOG(@"DownloadItem::terminateTask end");
}
-(void)removeFromNotificationCenter
{
    NSLOG(@"DownloadItem::removeFromNotificationCenter");
    [[NSNotificationCenter defaultCenter] 
        removeObserver:self 
        name:NSTaskDidTerminateNotification 
        object:wgetTask];
    [[NSNotificationCenter defaultCenter] 
        removeObserver:self 
        name:NSFileHandleReadCompletionNotification 
        object:[wgetPipe fileHandleForReading]];
}

-(NSArray *)getArgument
{
    NSMutableArray *arguments=[[[NSMutableArray alloc]initWithCapacity:10]autorelease];

    id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];
    NSString *downloadFolder=[[userDefaults valueForKey:@"downloadFolder"]stringByExpandingTildeInPath];
    
    if(downloadFolder){
		//20060520 added folder check
		NSFileManager *fileManager=[NSFileManager defaultManager];
		BOOL isDirectory;
		BOOL isExists=[fileManager fileExistsAtPath:downloadFolder isDirectory:&isDirectory];
		if(isExists==NO){
			//NSLOG(@"isExists==NO");
			//NSLOG(downloadFolder);
			downloadFolder=[[NSString stringWithFormat:@"~/Desktop"]stringByExpandingTildeInPath];
			//NSLOG(downloadFolder);
		}
		
		[arguments addObject: [NSString stringWithFormat:@"--directory-prefix=%@",downloadFolder]];
    }
	
    if([resume boolValue])
        [arguments addObject:[NSString stringWithFormat:@"-c"]];
    
    if([checkTimeStamp boolValue])
        [arguments addObject:[NSString stringWithFormat:@"-N"]];
    
    if([[userDefaults valueForKey:@"numberOfRetries"] intValue])
        [arguments addObject:[NSString stringWithFormat:@"-t%d",[[userDefaults valueForKey:@"numberOfRetries"] intValue]]];
    
    if([[userDefaults valueForKey:@"timeOut"] intValue])
        [arguments addObject:[NSString stringWithFormat:@"-T%d",[[userDefaults valueForKey:@"timeOut"] intValue]]];
        
    
    BOOL useProxy=NO;
    useProxy=[[userDefaults valueForKey:@"useProxy"] boolValue];
    
    if(useProxy) [arguments addObject:[NSString stringWithFormat:@"--proxy=on"]];
    else [arguments addObject:[NSString stringWithFormat:@"--proxy=off"]];
    
    int maxFileSize=[[userDefaults valueForKey:@"maxFileSize"] intValue];
    [arguments addObject:[NSString stringWithFormat:@"-Q%d",maxFileSize*1024*1024]];
        
    NSString* user_agent=[userDefaults valueForKey:@"userAgent"];
        
    if(user_agent && [user_agent isEqualToString:@""]==NO)
        [arguments addObject:[NSString stringWithFormat:@"--user-agent=%@",user_agent]];
    
 
    if(httpUser && [httpUser isEqualToString:@""]==NO)
        [arguments addObject:[NSString stringWithFormat:@"--http-user=%@",httpUser]];
    
    if(httpPassword && [httpPassword isEqualToString:@""]==NO)
        [arguments addObject:[NSString stringWithFormat:@"--http-passwd=%@",httpPassword]];
    
    BOOL passive_ftp=[[userDefaults valueForKey:@"usePassiveFTP"] boolValue];
    
    if(passive_ftp) [arguments addObject:[NSString stringWithFormat:@"--passive-ftp"]];
    
    if((referer)&&([referer isEqualToString:@""]==NO))
        [arguments addObject:[NSString stringWithFormat:@"--header=REFERER:%@",referer]];
     
    //20050419
    BOOL convertToRelativePath=[[userDefaults valueForKey:@"convertToRelativePath"] boolValue];
    if(convertToRelativePath)  [arguments addObject:[NSString stringWithFormat:@"-k"]];
        
    
    if([recursive boolValue]) {
        [arguments addObject:[NSString stringWithFormat:@"-r"]];
        
        [arguments addObject:[NSString stringWithFormat:@"-l%d",[recursiveLevel intValue]]];

        NSString* fileTypeAllow=[userDefaults valueForKey:@"fileTypeAllow"];
        if((fileTypeAllow)&&([fileTypeAllow isEqualToString:@""]==NO))
            [arguments addObject:[NSString stringWithFormat:@"-A%@",fileTypeAllow]];
        
        NSString* fileTypeDeny=[userDefaults valueForKey:@"fileTypeDeny"];
        if((fileTypeDeny)&&([fileTypeDeny isEqualToString:@""]==NO))
            [arguments addObject:[NSString stringWithFormat:@"-R%@",fileTypeDeny]];
            
        NSString* domainAllow=[userDefaults valueForKey:@"domainAllow"];
        if((domainAllow)&&([domainAllow isEqualToString:@""]==NO))
            [arguments addObject:[NSString stringWithFormat:@"-D%@",domainAllow]];
 
        NSString* domainDeny=[userDefaults valueForKey:@"domainDeny"];
        if((domainDeny)&&([domainDeny isEqualToString:@""]==NO))
            [arguments addObject:[NSString stringWithFormat:@"--exclude-domains=%@",domainDeny]];

        NSString* directoryAllow=[userDefaults valueForKey:@"directoryAllow"];
        if((directoryAllow)&&([directoryAllow isEqualToString:@""]==NO))
            [arguments addObject:[NSString stringWithFormat:@"--include-directories=%@",directoryAllow]];

        NSString* directoryDeny=[userDefaults valueForKey:@"directoryDeny"];
        if((directoryDeny)&&([directoryDeny isEqualToString:@""]==NO))
            [arguments addObject:[NSString stringWithFormat:@"--exclude-directories=%@",directoryDeny]];


        switch([recursiveType intValue]){
            case 0:
            [arguments addObject:[NSString stringWithFormat:@"--no-parent"]];
            break;
            case 1:
            
            break;
            case 2:
            [arguments addObject:[NSString stringWithFormat:@"--span-hosts"]];
            break;
            default:
            break;
        }
        
        //if(no_clobber) [arguments addObject:[NSString stringWithFormat:@"-nc"]];
            
	}
    
    //20081213
    [arguments addObject:@"--progress=dot:binary"]; 
    
	//20050910
	NSString* otherWgetOptions=[userDefaults valueForKey:@"otherWgetOptions"];
	if( otherWgetOptions && ([otherWgetOptions isEqualToString:@""]==NO)){
		[arguments addObject:otherWgetOptions];
		//NSLOG(otherWgetOptions);
	}else{
		//NSLOG(@"otherWgetOptions is null");
	}

	// url 
	[arguments addObject:url];
    
    return arguments;
}

-(BOOL)isCocoaWgetWgetrc
{
    #define COCOAWGET_WGETRC_HEADER @"# Generated by CocoaWget\n"
    
    NSError *error = nil;
    NSString *str=[NSString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/.wgetrc",NSHomeDirectory()] encoding:NSUTF8StringEncoding error:&error];
    if (!str) return NO;
    return [str hasPrefix:COCOAWGET_WGETRC_HEADER];
}
-(void)backupWgetrc
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *filePath,*backupPath;
    NSError *error = nil;
    filePath=[NSString stringWithFormat:@"%@/.wgetrc",NSHomeDirectory()];
    backupPath=[NSString stringWithFormat:@"%@/.wgetrc.CocoaWget.backup",NSHomeDirectory()];
    if (([manager fileExistsAtPath:filePath])&&([self isCocoaWgetWgetrc]==NO)){
        [manager removeItemAtPath:backupPath error:&error];
        [manager copyItemAtPath:filePath toPath:backupPath error:&error];
    }
    NSLOG(@"backupWgetrc");
}

-(void)restoreWgetrc
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *filePath,*backupPath;
    NSError *error = nil;
    filePath=[NSString stringWithFormat:@"%@/.wgetrc",NSHomeDirectory()];
    backupPath=[NSString stringWithFormat:@"%@/.wgetrc.CocoaWget.backup",NSHomeDirectory()];
    if ([manager fileExistsAtPath:backupPath]){
        [manager removeItemAtPath:filePath error:&error];
        [manager copyItemAtPath:backupPath toPath:filePath error:&error];
    }
    NSLOG(@"restoreWgetrc");
}

-(void)updateWgetrc
{
    NSLOG(@"updateWgetrc");
    NSString *filePath;
    NSMutableString *contents;
    filePath=[NSString stringWithFormat:@"%@/.wgetrc",NSHomeDirectory()];
    //NSLOG(filePath);
    contents=[[[NSMutableString alloc] initWithCapacity:256]autorelease];
    
    [contents appendFormat:COCOAWGET_WGETRC_HEADER];
    
    id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];

    BOOL useProxy=[[userDefaults valueForKey:@"useProxy"] boolValue];
    if(useProxy){
        [contents appendFormat:@"use_proxy = on \n"];
        
        NSString* httpProxy=[userDefaults valueForKey:@"httpProxy"];
        if(httpProxy && [httpProxy isEqualToString:@""]==NO)
            [contents appendFormat:@"http_proxy=%@\n",httpProxy];
         
        NSString* ftpProxy=[userDefaults valueForKey:@"ftpProxy"];
        if(ftpProxy && [ftpProxy isEqualToString:@""]==NO)
            [contents appendFormat:@"ftp_proxy=%@\n",ftpProxy];
            
        NSString* proxyUser=[userDefaults valueForKey:@"proxyUser"];
        if(proxyUser && [proxyUser isEqualToString:@""]==NO)
            [contents appendFormat:@"proxy_user=%@\n",proxyUser];

        NSString* proxyPassword=[userDefaults valueForKey:@"proxyPassword"];
        if(proxyPassword && [proxyPassword isEqualToString:@""]==NO)
            [contents appendFormat:@"proxyPassword=%@\n",proxyPassword];
            
    }
    else {
        [contents appendFormat:@"use_proxy = off \n"];
    }
    //NSLog(contents);
    
    [contents writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:NULL ];
}
@end
