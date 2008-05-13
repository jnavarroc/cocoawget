#import "CWArrayController.h"
#import "DownloadItem.h"


@interface CWArrayController (Private)
    -(void)updateLogView:(DownloadItem*)item;
    -(void)timerFired;
    -(void)loadDrawerSize;
    -(void)saveDrawerSize;
    -(void)updateButton;
    
@end


@implementation CWArrayController
-(void)awakeFromNib
{
    [self loadList];
    
    [tableView registerForDraggedTypes:[NSArray arrayWithObjects:NSStringPboardType,nil]];

    
    
    // load apple script
    NSString *filePath=[[[NSBundle mainBundle]resourcePath]
    stringByAppendingPathComponent : @"GetURLFromSafari.scpt" ];

    
    NSURL *fileURL=[NSURL fileURLWithPath:filePath];
    
    NSDictionary *err;
    appleScript=[[NSAppleScript alloc]initWithContentsOfURL:fileURL error:&err];
    if(! appleScript){
        NSLOG(@"%@",fileURL);
        NSLOG(@"NSAppleScript::load err = %@", err);
    }
    if (! [appleScript compileAndReturnError: &err]) {
        NSLOG(@"NSAppleScript::compileAndReturnError err = %@", err);
        [appleScript release];
    }

    [self loadDrawerSize];
    
    
    //start timer
    id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];
    BOOL autoDownload=[[userDefaults valueForKey:@"autoDownload"]boolValue];
    if(autoDownload) [self startTimer];

   
}

-(void)clear
{
    NSLOG(@"CWArrayController::clear"); 
    
    [self saveDrawerSize];
    [self stopTimer];
    
    //remove files
    id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];
    int removeType=[[userDefaults valueForKey:@"removeDownloadOption"]intValue];
    if(removeType==1) {
        [self removeFinishedDownload];
    }
    [self saveList];
    
    
    //clean list
    NSMutableArray *list=[self content];
    int i;
    for(i=0;i<[list count];i++){
        DownloadItem *data=[list objectAtIndex:i];
        if([data isDownloading]){
            [data stopDownload];
        }
    }
    [list removeAllObjects];
    
    
    [appleScript release];
}

-(void)dealloc
{
    NSLOG(@"CWArrayController::dealloc");
    [self clear];
    [super dealloc];
}




#pragma mark  ------------------ timer --------------------
-(void)startTimer
{
    NSLOG(@"CWArrayController::startTimer");
    
    [timer release];
    
    // start timer
    timer = [[NSTimer scheduledTimerWithTimeInterval:5.0 
			target:self				// Target is this object
			selector:@selector(timerFired)		// What function are we calling
			userInfo:nil repeats:YES]		// No userinfo / repeat infinitely
			retain]; 				// No autorelease
    
    // Add our timers to the EventTracking loop
    [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSEventTrackingRunLoopMode];
    
}

-(void)stopTimer
{
    NSLOG(@"CWArrayController::stopTimer"); 
    [timer invalidate];
    [timer release];
    timer=nil;
}

-(BOOL)isTimerRunning
{
    if(!timer) return NO;
    else return [timer isValid];
}


-(void)loadList
{
    NSLOG(@"CWArrayController::loadList");
    id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];
    if(userDefaults){
        NSString *version=[userDefaults valueForKey:@"version"];
        if(version && [version isEqualToString:@"2.0"]){
        [userDefaults setValue:@"" forKey:@"url"];
        [userDefaults setValue:@"" forKey:@"referer"];
        NSArray *list=[userDefaults valueForKey:@"list"];
        
        if(list){
        //NSLOG("%@",[list class]);
        int i;
        for(i=0;i<[list count];i++){
            id listItem=[list objectAtIndex:i];
            
            DownloadItem *data=[[[DownloadItem alloc]init]autorelease];
            [data setDelegate:self];
            [self copyValueForKey:@"url" from:listItem to:data];
            [self copyValueForKey:@"httpUser" from:listItem to:data];
            [self copyValueForKey:@"httpPassword" from:listItem to:data];
            [self copyValueForKey:@"referer" from:listItem to:data];
            [self copyValueForKey:@"resume" from:listItem to:data];
            [self copyValueForKey:@"checkTimeStamp" from:listItem to:data];
            [self copyValueForKey:@"recursive" from:listItem to:data];
            [self copyValueForKey:@"recursiveType" from:listItem to:data];
            [self copyValueForKey:@"recursiveLevel" from:listItem to:data];
            //[self copyValueForKey:@"status" from:listItem to:data];
            [self addObject:data];
        }
        }

        }else{
            NSLOG(@"version error");
            [self createUserDefaults];
        }
    }else{
         NSLOG(@"userDefaults is nil");
    }

}

-(void)saveList
{
    NSLOG(@"CWArrayController::saveList");
    id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];
    if(userDefaults){
        id list=[self content];
        int i;
        NSMutableArray *saveList=[NSMutableArray arrayWithCapacity:4];
        for(i=0;i<[list count];i++){
            NSMutableDictionary *dict=[NSMutableDictionary dictionaryWithCapacity:8];
            id data=[list objectAtIndex:i];
            [self copyValueForKey:@"url" from:data to:dict];
            [self copyValueForKey:@"httpUser" from:data to:dict];
            [self copyValueForKey:@"httpPassword" from:data to:dict];
            [self copyValueForKey:@"referer" from:data to:dict];
            [self copyValueForKey:@"resume" from:data to:dict];
            [self copyValueForKey:@"checkTimeStamp" from:data to:dict];
            [self copyValueForKey:@"recursive" from:data to:dict];
            [self copyValueForKey:@"recursiveType" from:data to:dict];
            [self copyValueForKey:@"recursiveLevel" from:data to:dict];
            //[self copyValueForKey:@"status" from:data to:dict];
            [saveList addObject:dict];
        }
        //NSLOG(@"%@",saveList);
        [userDefaults setValue:saveList forKey:@"list"];
    }
}

-(void)createUserDefaults
{
    //default parameters
    NSLOG(@"CWArrayController::createUserDefaults");
    id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];
    if(userDefaults){
    
        [userDefaults setValue:[NSNumber numberWithBool:YES] forKey:@"resume"];
        [userDefaults setValue:@"0" forKey:@"recursiveType"];
        [userDefaults setValue:@"~/Desktop" forKey:@"downloadFolder"];
        [userDefaults setValue:@"2" forKey:@"removeDownloadOption"];
        [userDefaults setValue:@"5" forKey:@"maxConnections"]; 
        [userDefaults setValue:@"2" forKey:@"recursiveLevel"]; 
        [userDefaults setValue:[NSNumber numberWithBool:YES] forKey:@"usePassiveFTP"]; 
        
        
        [userDefaults setValue:@"2.0" forKey:@"version"];
    }

}


/*
http://homepage.mac.com/mkino2/cocoaProg/Foundation/NSString/NSString.html#parseStringAsLines
*/
- (NSArray*)parseAsLines:(NSString*)string
{
    NSString* parsedString;
    NSRange range, subrange,subrange2;
    int length;
    NSMutableArray* parsedStrings=[[NSMutableArray alloc]initWithCapacity:1];
    
    length = [string length];
    range = NSMakeRange(0, length);
    while(range.length > 0) {
        subrange = [string lineRangeForRange:
            NSMakeRange(range.location, 0)];
        if(subrange.length!=range.length){
        subrange2.location=subrange.location;
        subrange2.length=subrange.length-1; 
        }else{
        subrange2=subrange;
        }
        //NSLOG(@"%d %d %d %d",subrange.location,subrange.length,range.location,range.length);
        parsedString = [string substringWithRange:subrange2];
        [parsedStrings addObject:[parsedString copy] ];
        //printf("line: %s\n", [string cString]);
        
        range.location = NSMaxRange(subrange);
        range.length -= subrange.length;
    }
    return parsedStrings;
}

- (NSString*) validateURL:(NSString*)originalURL
{    
    NSString* convertedURL=originalURL;
    
    /* convret ttp://  => http://  */
    if((originalURL)&&([originalURL hasPrefix:@"ttp"])){
        convertedURL=[NSString stringWithFormat:@"h%@",originalURL];
    }
    return convertedURL;
}


/*
http://domain/image[000-999].jpg
->
http://domain/image000.jpg
http://domain/image001.jpg
...
http://domain/image999.jpg
*/
// return array of NSString
-(NSArray*) expandSequencialURL:(NSString*)url
{
    NSMutableArray* array=nil;
    int pos1=-1;// position of [
    int pos2=-1;// position of ]
    int pos3=-1;// position of -
    int len=[url cStringLength];
    BOOL isExpanded=NO;
    char *cStr=(char*)malloc((len+2)*sizeof(char));
    int i;
    [url getCString:cStr];
    for(i=0;i<len;i++){
        char c=cStr[i];
        if(c=='[') pos1=i;
        if((c==']')&&(pos1!=-1)) pos2=i;
    }
    if((pos1!=-1)&&(pos2!=-1)){
        for(i=pos1+1;i<pos2;i++){
            if(cStr[i]=='-') pos3=i;
        }
        if(pos3!=-1){
            BOOL isValid=YES;
            for(i=pos1+1;i<pos2;i++){
                if(i!=pos3){
                    if(isdigit(cStr[i])==0){
                        isValid=NO;
                        break;
                    }
                }
            }
            if(isValid){
                char startNumStr[4096];
                char endNumStr[4096];
                for(i=0;i<pos3-pos1-1;i++){
                    startNumStr[i]=cStr[i+pos1+1];
                }
                startNumStr[i]='\0';
                for(i=0;i<pos2-pos3-1;i++){
                    endNumStr[i]=cStr[i+pos3+1];
                }
                endNumStr[i]='\0';
                int startNum=atoi(startNumStr);
                int endNum=atoi(endNumStr);
                                
                if(startNum>endNum){
                    int tmp=startNum;
                    startNum=endNum;
                    endNum=tmp;
                }
                //NSLOG(@"pos %d %d %d",pos1,pos2,pos3);
                //NSLOG([NSString stringWithCString:startNumStr]);
                //NSLOG([NSString stringWithCString:endNumStr]);
                

                //NSLOG(@"range %d - %d",startNum,endNum);
                int length1=pos3-pos1-1;
                int length2=pos2-pos3-1;
                int length=length2;
                if(length1>length2) length=length1;
                char formatStr[4096];
                char digitStr[4096];
                char headerStr[4096];
                char footerStr[4096];
                char str[4096];
                
                for(i=0;i<pos1;i++){
                    headerStr[i]=cStr[i];
                }
                headerStr[i]='\0';
                
                for(i=0;i<len-pos2-1;i++){
                    footerStr[i]=cStr[i+pos2+1];
                }
                footerStr[i]='\0';
                //NSLOG(@"length=%d",length);
                sprintf(formatStr,"%%.%dd",length);
                array=[NSMutableArray arrayWithCapacity:100];	    
                for(i=startNum;i<=endNum;i++){
                    sprintf(digitStr,formatStr,i);
                    sprintf(str,"%s%s%s",headerStr,digitStr,footerStr);
                    NSString* aURL=[NSString stringWithCString:str];
                    //NSLOG(aURL);
                    [array addObject:aURL];
                }
                isExpanded=YES;
            }
            
        }
    }
    free(cStr);
    
    if(isExpanded==NO){
        array=[NSArray arrayWithObject:url];
    }
    return array;
}


-(NSArray*)parseURL:(NSString*)str
{
    NSMutableArray *array=[NSMutableArray arrayWithCapacity:1];
    
    NSArray *lines=[self parseAsLines:str];
    int i,j;
    for(i=0;i<[lines count];i++){
        NSString* line=[lines objectAtIndex:i];
        NSArray *urls=[self expandSequencialURL:line];
        for(j=0;j<[urls count];j++){
            NSString *url=[urls objectAtIndex:j];
            url=[self validateURL:url];
            [array addObject:url];
        }//j
        
    }//i

    return array;
}

- (IBAction)addToList:(id)sender
{
    id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];
    
    //NSString *url=[userDefaults valueForKey:@"url"];

    NSString *url=[urlTextField stringValue];
    [userDefaults setValue:url forKey:@"url"];
    
    if((!url)||([url  isEqualToString:@""])) return;
    
    NSArray  *urls=[self parseURL:url];
    int i=0;
    int urlCount=[urls count];
    for(i=0;i<urlCount;i++){
        NSString *u=[urls objectAtIndex:i];
        if(urlCount>1) [self addURLWithOutChecking:u];
        else [self addURL:u];
    }
}

-(void)copyValueForKey:(NSString*)key from:(id)srcObj to:(id)dstObj
{
    if(srcObj==dstObj) return;
    
    id value=[srcObj valueForKey:key];
    
    if(value) [dstObj setValue:[value copy] forKey:key];
    
}

-(BOOL)isURLInList:(NSString *)urlString
{
    //check same url
    NSArray* list=[self content];
    //NSLOG(@"%@",[list class]);
    int i=0;
    for(i=0;i<[list count];i++){
        NSString *urlInList=[[list objectAtIndex:i] valueForKey:@"url"];
        //NSLOG(urlInList);
        if([urlString isEqualToString:urlInList]) return YES;
    }
    return NO;
}

-(DownloadItem *)downloadItem:(NSString *)urlString
{
    DownloadItem *data=[[[DownloadItem alloc]init]autorelease];
    [data setDelegate:self];
    [data setValue:urlString  forKey:@"url"];
    
    id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];
    [self copyValueForKey:@"httpUser" from:userDefaults to:data];
    [self copyValueForKey:@"httpPassword" from:userDefaults to:data];
    
    [self copyValueForKey:@"referer" from:userDefaults to:data];
    [self copyValueForKey:@"resume" from:userDefaults to:data];
    [self copyValueForKey:@"checkTimeStamp" from:userDefaults to:data];
    [self copyValueForKey:@"recursive" from:userDefaults to:data];
    [self copyValueForKey:@"recursiveType" from:userDefaults to:data];
    [self copyValueForKey:@"recursiveLevel" from:userDefaults to:data];
    
    
    
    BOOL autoDownload=[[userDefaults valueForKey:@"autoDownload"]boolValue];
    
    /*
    if((autoDownload)&&([self downloadShouldStart:data])){
        [data startDownload];
    }
    */
    
    if(!autoDownload){
        [self setSelectionIndexes:nil];//deselect
    }
    
    return data;
}

-(NSString*)domain:(NSString*)url
{
    NSURL *aURL=[NSURL URLWithString:url];
    if(!aURL) return url;
    return [aURL host];
}

-(BOOL)downloadShouldStart:(DownloadItem*)data
{
    int downloadingCount=[self downloadingCount];
    int maxConnections=1+[[[[NSUserDefaultsController sharedUserDefaultsController] values] valueForKey:@"maxConnections"] intValue];
    NSString *domain=[self domain:[data valueForKey:@"url"]];
    //NSLOG(@"%@",domain);
    if(
        (downloadingCount<maxConnections) &&
        ([[data valueForKey:@"status"] isEqualToString:WAITING] ) &&
        ([self downloadingCountInDomain:domain]==0)
    )
        {
        return YES;
    }
    return NO;

}

-(void)addURLWithOutChecking:(NSString *)urlString
{        
    if([urlString isEqualToString:@""]) return;
    if([urlString isEqualToString:@"\n"]) return;
    
    DownloadItem *data=[self downloadItem:urlString];
    
    [self addObject:data];
}

-(void)addURL:(NSString *)urlString
{
    if([urlString isEqualToString:@""]) return;
    if([urlString isEqualToString:@"\n"]) return;


    if([self isURLInList:urlString]) return;
        
    DownloadItem *data=[self downloadItem:urlString];
    
    [self addObject:data];

}
-(void)insertURL:(NSString *)urlString atArrangedObjectIndex:(unsigned int)index
{
    if([self isURLInList:urlString]) return;
        
    DownloadItem *data=[self downloadItem:urlString];
    [self insertObject:data atArrangedObjectIndex:index];
}


- (IBAction)delete:(id)sender
{
    [self remove:sender];
    
    [self tableViewSelectionDidChange:nil];
}

- (IBAction)startStop:(id)sender
{
    id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];
    BOOL autoDownload=[[userDefaults valueForKey:@"autoDownload"]boolValue];
    
    if(autoDownload){
    NSArray *selectedObjects=[self selectedObjects];
    int i;
    for(i=0;i<[selectedObjects count];i++){
        id downloadItem=[selectedObjects objectAtIndex:i];
        [downloadItem startStop];
    }
    int selectedCount=[selectedObjects count];
    if(selectedCount==1){
        id downloadItem=[selectedObjects objectAtIndex:0];
        if([downloadItem isDownloading]){
            [startButton setTitle:NSLocalizedString(@"Stop",@"")];
        }else{
            [startButton setTitle:NSLocalizedString(@"Start",@"")];
        }
    }else if(selectedCount==0){
    
        int downloadingCount=[self downloadingCount];
        int totalCount=[[self content]count];
        if(downloadingCount==0){
            [startButton setTitle:NSLocalizedString(@"Stop",@"")];
        }else if(downloadingCount==totalCount){
            [startButton setTitle:NSLocalizedString(@"Start",@"")];
        }else{
        }
        
        id list=[self content];
        for(i=0;i<[list count];i++){
            DownloadItem *downloadItem=[list objectAtIndex:i];
            if([[downloadItem valueForKey:@"status"] isEqualToString:FINISHED]==NO){
            if(downloadingCount==0) [downloadItem startDownload];
            else if(downloadingCount==totalCount) [downloadItem stopDownload];
            }
        }
    
    }
    }else{ //autodownload ==NO
        if([self isTimerRunning]) {
            [self stopTimer];
            [self stopAll];
            
        }else {
            [self startTimer];
            [self timerFired];
        }
    }
    [self tableViewSelectionDidChange:nil];
}
-(void)stopAll
{
    id list=[self content];
    int i;
    for(i=0;i<[list count];i++){
        DownloadItem *downloadItem=[list objectAtIndex:i];
        if([downloadItem isDownloading]) [downloadItem stopDownload];
        if([[downloadItem valueForKey:@"status"] isEqualToString:FINISHED]==NO){
            [downloadItem setValue:WAITING forKey:@"status"];
        }
    }
}

- (IBAction)setURL:(id)sender
{
    //NSLOG(@"CWArrayController::setURL");
    /*NSArray *selectedObjects=[self selectedObjects];
    if([selectedObjects count]==1){
        id data=[selectedObjects objectAtIndex:0];
        id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];
        [self copyValueForKey:@"url" from:userDefaults to:data];
    }*/
    [self setSelectionIndexes:nil];//deselect
}

-(void)copyUserDefaultToSelectedDataForKey:(NSString*)key
{
    NSArray *selectedObjects=[self selectedObjects];
    if([selectedObjects count]==1){
        id data=[selectedObjects objectAtIndex:0];
        id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];
        [self copyValueForKey:key from:userDefaults to:data];
    }
}

- (IBAction)setHTTPUser:(id)sender
{
    [self copyUserDefaultToSelectedDataForKey:@"httpUser"];
}

- (IBAction)setHTTPPassword:(id)sender
{
    [self copyUserDefaultToSelectedDataForKey:@"httpPassword"];
}

- (IBAction)setReferer:(id)sender;
{
    [self copyUserDefaultToSelectedDataForKey:@"referer"];
}

- (IBAction)setResume:(id)sender
{
    [self copyUserDefaultToSelectedDataForKey:@"resume"];
}

- (IBAction)setCheckTimeStamp:(id)sender
{
    [self copyUserDefaultToSelectedDataForKey:@"checkTimeStamp"];
}

- (IBAction)setRecursive:(id)sender
{
    [self copyUserDefaultToSelectedDataForKey:@"recursive"];
}

- (IBAction)setRecursiveType:(id)sender
{
    [self copyUserDefaultToSelectedDataForKey:@"recursiveType"];
}

- (IBAction)setRecursiveLevel:(id)sender
{
    [self copyUserDefaultToSelectedDataForKey:@"recursiveLevel"];
}

- (IBAction)setAutoDownload:(id)sender
{
    id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];
    BOOL autoDownload=[[userDefaults valueForKey:@"autoDownload"]boolValue];
    if(autoDownload) {
        if([self isTimerRunning]==NO) [self startTimer];
    }else{
        if([self isTimerRunning]) {
            [self stopTimer];
            [self stopAll];
        }
        [startButton setEnabled:YES];
    }
}

- (IBAction)showLog:(id)sender
{
    //NSLog(@"showLog");
    id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];
    BOOL showLog=[[userDefaults valueForKey:@"showLog"]boolValue];
    //[userDefaults setValue:[NSNumber numberWithBool:!showLog] forKey:@"showLog"];
    if(showLog) {
        [(NSDrawer*)drawer open];
    }else{
        [(NSDrawer*)drawer close];
    }
}

-(int)downloadingCount
{
    NSArray* list=[self content];
    int count=0;
    int i;
    for(i=0;i<[list count];i++){
        DownloadItem *data=[list objectAtIndex:i];
        if([data isDownloading]){
            count++;
        }
    }
    return count;
}

-(int)downloadingCountInDomain:(NSString*)domain
{
    NSArray* list=[self content];
    int count=0;
    int i;
    for(i=0;i<[list count];i++){
        DownloadItem *data=[list objectAtIndex:i];
        if([data isDownloading]){
            NSString *dataDomain=[self domain:[data valueForKey:@"url"]];
            if([dataDomain isEqualToString:domain]){
                count++;
            }
        }
    }
    return count;
}

-(void)removeFinishedDownload
{
    NSLOG(@"CWArrayController::removeFinishedDownload");
    NSMutableArray* list=[self content];
    int i;
    for(i=0;i<[list count];i++){
        DownloadItem *data=[list objectAtIndex:i];
        if([[data valueForKey:@"status"] isEqualToString:FINISHED]){
            NSLOG(@"remove:%d",i);
            [list removeObjectAtIndex:i];
            i--;
        }
    }
}



-(void)timerFired
{
    //NSLOG(@"timerFired");
    
    if(![self isTimerRunning]) return;
    if(isChecking) return;
    isChecking=YES;
    
    
    NSArray* list=[self content];
    int i;
    for(i=0;i<[list count];i++){
        DownloadItem *data=[list objectAtIndex:i];
        if([self downloadShouldStart:data]){
            [data startDownload];
            break;
        }
    }
    
    isChecking=NO;
    
}

-(BOOL)isSarariRunning
{
    BOOL flag=NO;
    NSEnumerator *e=[[[NSWorkspace sharedWorkspace] launchedApplications] objectEnumerator];
    id cur;
    while (cur=[e nextObject]) {
        if ([[cur objectForKey:@"NSApplicationName"] isEqualToString:@"Safari"]) {
            flag=YES;
            break;
        }
    }
    return flag;
}

-(void)getRefererFromSafari
{
    if([self isSarariRunning]){
    //NSLOG(@"getRefererFromSafari");
    NSString *referer=nil;
    NSDictionary *err;
    NSAppleEventDescriptor *result;
    result = [appleScript executeAndReturnError: &err];
    if(result){
        /*
        NSAppleEventDescriptor *unicodeResult=[result coerceToDescriptorType:typeUnicodeText];
        NSData* unicodeData = [unicodeResult data];
        NSString* resultString = [[[NSString alloc] initWithCharacters:
        (unichar*)[unicodeData bytes] length:[unicodeData length] / sizeof(unichar)]autorelease];
        
        NSLOG(resultString);
        referer=resultString;
        */
        referer=[result stringValue];
        NSLOG(referer);
        

        id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];
        if(referer)[userDefaults setValue:referer forKey:@"referer"];
    }
    //NSLOG(@"getRefererFromSafari end");
    }
}

//DownloadItem delegate
-(void)logUpdated:(DownloadItem*)item
{
    [self updateLogView:item];
}

-(void)downloadFinished:(DownloadItem*)item
{
    NSLOG(@"CWArrayController::downloadFinished");
    
    [self saveList];
    
    //[self showLog:nil];
    
    id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];
    
    
    BOOL openFile=[[userDefaults valueForKey:@"openFilesAfterDownloading"]boolValue];
    BOOL isRecursive=[[item valueForKey:@"recursive"]boolValue];
    NSString* downloadFolder=[[userDefaults valueForKey:@"downloadFolder"] stringByExpandingTildeInPath];
    NSString* url=[item valueForKey:@"url"];
    NSString* fileName=[url lastPathComponent];
    NSString* filePath=[item valueForKey:@"downloadedFilePath"];
	NSLOG(@"filePath:%@",filePath);
	if((filePath==nil)||([[NSFileManager defaultManager]fileExistsAtPath:filePath]==NO)){
		filePath=[downloadFolder stringByAppendingPathComponent:fileName];
    }    
    
    //write comment
    BOOL saveURLAsComment=[[userDefaults valueForKey:@"saveURLAsComment"]boolValue];
    if((saveURLAsComment)&&(isRecursive==NO)){
        if([[NSFileManager defaultManager]fileExistsAtPath:filePath]){
            [self writeComment:url toFile:filePath];
        }
    }
    
    //open file
    if((openFile)/*&&(isRecursive==NO)*/){
        NSLOG(@"openFile: %@",filePath);
        if([[NSFileManager defaultManager]fileExistsAtPath:filePath]){
            [[NSWorkspace sharedWorkspace] openFile:filePath];
        }
    }
    
    
    
    
    //remove finished file
    int removeType=[[userDefaults valueForKey:@"removeDownloadOption"]intValue];
    if((removeType==2) && ([[item valueForKey:@"status"] isEqualToString:FINISHED])){
        [self removeObject:item];
    }
    

    BOOL autoDownload=[[userDefaults valueForKey:@"autoDownload"]boolValue];
    if(autoDownload==NO){
        if([[self content]count]==0){
            if([self isTimerRunning]) [self stopTimer];
        }
    }
    
    [self tableViewSelectionDidChange:nil];
}

-(void)writeComment:(NSString*) comment toFile:(NSString*)filePath
{
    if((!comment)||(!filePath)) return;
    
    NSString *scriptText;
    NSAppleScript *script;
    
    CFURLRef fileURL = CFURLCreateWithFileSystemPath(NULL, (CFStringRef)filePath, kCFURLPOSIXPathStyle, NO);
    NSString *hfsPath = (NSString *)CFURLCopyFileSystemPath(fileURL, kCFURLHFSPathStyle);
    CFRelease(fileURL);
        
    scriptText = [NSString stringWithFormat:@"tell application \"Finder\" to set comment of item \"%@\" to \"%@\"", hfsPath, comment];
    //NSLOG(scriptText);
    script = [[[NSAppleScript alloc] initWithSource:scriptText] autorelease];
    [script executeAndReturnError:nil];
}

-(void)updateDownloadInfo
{
    NSArray *selectedObjects=[self selectedObjects];
    if([selectedObjects count]==1){
    
        id data=[selectedObjects objectAtIndex:0];
        
        id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];
        [self copyValueForKey:@"url" from:data to:userDefaults];
        [self copyValueForKey:@"httpUser" from:data to:userDefaults];
        [self copyValueForKey:@"httpPassword" from:data to:userDefaults];
        [self copyValueForKey:@"referer" from:data to:userDefaults];
        [self copyValueForKey:@"resume" from:data to:userDefaults];
        [self copyValueForKey:@"checkTimeStamp" from:data to:userDefaults];
        [self copyValueForKey:@"recursive" from:data to:userDefaults];
        [self copyValueForKey:@"recursiveType" from:data to:userDefaults];
        [self copyValueForKey:@"recursiveLevel" from:data to:userDefaults];
    }
}

-(void)updateLogView:(DownloadItem*)item
{
    //NSLog(@"CWArrayController::updateLogView");

    if([drawer state]==NSDrawerOpenState){
        NSArray *selectedObjects=[self selectedObjects];
        if([selectedObjects count]==1){
            DownloadItem* downloadItem=[selectedObjects objectAtIndex:0];
            if(item==downloadItem || item==nil){
                if(downloadItem){
                    NSString *log=[downloadItem logString];
                    
                    [logView setString:log];
                        
                    int length=[log length];
                    [logView scrollRangeToVisible: NSMakeRange(length,0)];
                    
                }
            }
        }else{
            [logView setString:@""];//clear log
        }
    }

}
-(void)updateButton
{

    id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];
    BOOL autoDownload=[[userDefaults valueForKey:@"autoDownload"]boolValue];
    if(autoDownload){
    NSArray *selectedObjects=[self selectedObjects];
    if([selectedObjects count]==1){
    
        //update GUI
        
        
        DownloadItem* data=[selectedObjects objectAtIndex:0];
        
        
        [startButton setEnabled:YES];
        if([data isDownloading]){
            [startButton setTitle:NSLocalizedString(@"Stop",@"")];
        }else{
            [startButton setTitle:NSLocalizedString(@"Start",@"")];
        }
    }else if([selectedObjects count]>1){
        id data=[selectedObjects objectAtIndex:0];
        
        BOOL isDownloading=[data isDownloading];
        BOOL sameState=YES;
        unsigned int i;
        for(i=1;i<[selectedObjects count];i++){
            if(isDownloading!=[[selectedObjects objectAtIndex:i]isDownloading]){
                sameState=NO;
                break;
            }
        }
        if(sameState){
            if(isDownloading){
                [startButton setTitle:NSLocalizedString(@"Stop",@"")];
            }else{
                [startButton setTitle:NSLocalizedString(@"Start",@"")];
            }
            [startButton setEnabled:YES];
        
        }else{
        
            [startButton setEnabled:NO];
        
        }
    
    }else{
        // no item
        int downloadingCount=[self downloadingCount];
        int totalCount=[[self content]count];
        if(downloadingCount==0){
            [startButton setTitle:NSLocalizedString(@"Start",@"")];
            [startButton setEnabled:YES];
        }else if(downloadingCount==totalCount){
            [startButton setTitle:NSLocalizedString(@"Stop",@"")];
            [startButton setEnabled:YES];
        }else{
            [startButton setEnabled:NO];
        }
    }
    
    }else{ //autodownload =NO
        [startButton setEnabled:YES];
        if([self isTimerRunning]) [startButton setTitle:NSLocalizedString(@"Stop",@"")];
        else [startButton setTitle:NSLocalizedString(@"Start",@"")];
            
    }

}

#pragma mark  ------------------ drawer --------------------
- (void)drawerDidOpen:(NSNotification *)notification
{
    [self updateLogView:nil];
}

- (void)drawerDidClose:(NSNotification *)notification
{
    id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];
    [userDefaults setValue:[NSNumber numberWithBool:NO] forKey:@"showLog"];
}


-(void)loadDrawerSize
{
    //update drawer size
    id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];
    int w=[[userDefaults valueForKey:@"drawerWidth"]intValue];
    int h=[[userDefaults valueForKey:@"drawerHeight"]intValue];
    
    if(h==0) h=40;
    [drawer setContentSize:NSMakeSize(w,h)];
    [self showLog:nil];
}

-(void)saveDrawerSize
{
    NSSize size=[drawer contentSize];
    int w=size.width;
    int h=size.height;
    id userDefaults=[[NSUserDefaultsController sharedUserDefaultsController] values];
    [userDefaults setValue:[NSNumber numberWithInt:w] forKey:@"drawerWidth"];
    [userDefaults setValue:[NSNumber numberWithInt:h] forKey:@"drawerHeight"];
}


#pragma mark  ------------------ tableView --------------------
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    //NSLOG(@"tableViewSelectionDidChange");
    
    [self updateButton];
    [self updateDownloadInfo];
    
    
    [self updateLogView:nil];
}

//-----------------------------------------------------
//tableView source  for drag and drop 


- (NSDragOperation)tableView:(NSTableView*)tv validateDrop:(id <NSDraggingInfo>)info proposedRow:(int)row proposedDropOperation:(NSTableViewDropOperation)op
{
    //NSLOG(@"validateDrop %d",row);
    int numberOfRows=[tv numberOfRows];
    if(row<0){
        [tv setDropRow:numberOfRows-1 dropOperation:NSTableViewDropAbove];
    }else{
        if(row>=numberOfRows) row=numberOfRows-1;
        [tv setDropRow:row dropOperation:NSTableViewDropOn];
    }
    if([info draggingSource]==tv) return NSDragOperationMove;
    else return NSDragOperationCopy;
}


- (BOOL)tableView:(NSTableView*)tv acceptDrop:(id <NSDraggingInfo>)info row:(int)row dropOperation:(NSTableViewDropOperation)op
{
    //NSLOG(@"acceptDrop %d->%d",draggingIndex,row);
    
    id draggingSource=[info draggingSource];
        
    
    NSPasteboard *myPasteboard=[info draggingPasteboard];
    
    NSArray *typeArray=[NSArray arrayWithObjects:NSStringPboardType,nil];
    NSString *availableType;
    NSArray *filesList;

    
    
    // find the best match of the types we'll accept and what's actually on the pasteboard
    availableType=[myPasteboard availableTypeFromArray:typeArray];
    //NSLOG(@"availableType:%@",availableType);
    
    // In the file format type that we're working with, get all data on the pasteboard
    filesList=[myPasteboard propertyListForType:availableType];
    

    // Insert url
    BOOL isAccepted=NO;
    
    if(draggingSource==tv){
        //swap object
        /*
        id obj1=[[self content]objectAtIndex:draggingIndex];
        [obj1 retain];
        id obj2=[[self content]objectAtIndex:row];
        [obj2 retain];
        [[self content] replaceObjectAtIndex:draggingIndex withObject:obj2];
        [[self content] replaceObjectAtIndex:row withObject:obj1];
        [obj1 release];
        [obj2 release];
        */
        [[self content]exchangeObjectAtIndex:row withObjectAtIndex:draggingIndex];
        
        [tableView selectRow:row byExtendingSelection:NO];
        isAccepted=YES;
    }
    else{
        
        //NSString* str=[filesList objectAtIndex:i];
        NSString* str=[myPasteboard stringForType:availableType];
        //NSString* url=[self validateURL:str];
        NSString* url=str;
        //NSLOG(@"%@",url);
        
        if( (url) &&( [url hasPrefix:@"http"] || [url hasPrefix:@"ftp"])){
        
            int newIndex=row;
            int length=[[self content] count];
            if(newIndex>length) newIndex=length;
            if(newIndex<0) newIndex=0;
            double interval=0.6;//0.2;
            if((newIndex<0)||(newIndex>=length-1)) {
                //[self addURL:url];
                [self performSelector:@selector(dropAddURL:) withObject:url afterDelay:interval];
                
            }
            else{
                //[self insertURL:url atArrangedObjectIndex:newIndex];
                NSArray *userInfo=[NSArray arrayWithObjects:url, 
                [NSNumber numberWithInt:newIndex],nil];
                [self performSelector:@selector(dropInsertURL:) withObject:userInfo afterDelay:interval];
                
            }
        
            isAccepted=YES;
        }
    
    }
    
    draggingIndex=-1;
    //[self updateListView];
    
    
    return isAccepted;
}

-(void) dropAddURL:(id)userInfo
{
    [self getRefererFromSafari];
    NSString *url=userInfo;
    [self addURL:url];
}

-(void) dropInsertURL:(id)userInfo
{
    [self getRefererFromSafari];
    NSArray *array=userInfo;
    NSString *url=[array objectAtIndex:0];
    int index=[[array objectAtIndex:1]intValue];
    [self insertURL:url atArrangedObjectIndex:index];
}

- (BOOL)tableView:(NSTableView *)tv writeRows:(NSArray*)rows toPasteboard:(NSPasteboard*)pboard
{
    int index=[[rows objectAtIndex:0]intValue];
    //int listSize=[urlList countInList:currentListName];
    //NSLOG(@"writeRows %d/%d",index,listSize);
    
    DownloadItem *item=[[self content] objectAtIndex:index];
    NSString* url=[item valueForKey:@"url"];
    
    NSArray *typeArray=[NSArray arrayWithObjects:NSStringPboardType,nil];
    [pboard declareTypes:typeArray owner:nil];

    NSString *availableType=[pboard availableTypeFromArray:typeArray];

    NSArray *filesList=[NSArray arrayWithObjects:url,nil];
    
    draggingIndex=index;
    [tableView selectRow:index byExtendingSelection:NO];
    
    return [pboard setPropertyList:filesList forType:availableType];

}


@end
