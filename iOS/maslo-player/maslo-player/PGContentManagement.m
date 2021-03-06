/******************************************************************************
 * PGContentManagement.m
 *
 * Copyright (c) 2011-2012, Academic ADL Co-Lab, University of Wisconsin-Extension
 * http://www.academiccolab.org/
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301  USA
 *****************************************************************************/
/*
 *  @author Cathrin Weiss (cathrin.weiss@uwex.edu)
 */
#import "sqlite3.h"
#import "PGContentManagement.h"
#import "ZipArchive.h"


@implementation PGContentManagement

@synthesize callbackId;
@synthesize downloadLocked;

-(CDVPlugin*) initWithWebView:(UIWebView*)theWebView
{
    self = (PGContentManagement*)[super initWithWebView:theWebView];
    self.downloadLocked = false;
    return self;
    
}


// initialize database
-(void)initializeDatabase:(NSMutableArray*)paramArray withDict:(NSMutableDictionary*)options {
    [self initDB];
}

// get path to content pack directory
-(void)getContentPath:(NSMutableArray*)paramArray withDict:(NSMutableDictionary*)options {
   NSString *callback = [paramArray pop];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [paths objectAtIndex:0];	
	NSString *contentPath = [documentsDirectory stringByAppendingPathComponent:@"Content"];
    [self sendCallbackData:callback withData:contentPath isSuccess:true];
}



// download content pack and install it
-(void) downloadContent:(NSMutableArray*)paramArray withDict:(NSMutableDictionary*)options {
    self.callbackId = [paramArray pop];
    if ([self downloadLocked]){
        [self performSelectorOnMainThread:@selector(downloadCompleteWithError:) withObject:@"Download locked" waitUntilDone:true];
        return;
    }
	[self performSelectorInBackground: @selector( downloadFile: ) withObject: paramArray ];
}

// unzip downloaded content
-(void) unzipContent:(NSMutableArray*)paramArray withDict:(NSMutableDictionary*)options {
    self.callbackId = [paramArray pop];
	[self performSelectorInBackground: @selector( unzipDownload: ) withObject: paramArray ];
}

// remove content pack 
-(void) removeContent:(NSMutableArray*)paramArray withDict:(NSMutableDictionary*)options  {
    NSString *title = [paramArray objectAtIndex:0];
    NSString *query = @"SELECT * FROM content WHERE title = ?";
    NSArray *arguments = [NSArray arrayWithObject:title];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [paths objectAtIndex:0];	
	
	NSString *newFilePath = [documentsDirectory stringByAppendingPathComponent:@"content.db"];
    NSMutableArray *results = [self readFromDatabase:newFilePath withQuery:query withArguments:arguments];
    if ([results count] > 0) {
        NSString *deletionPath = [[results objectAtIndex:0] objectAtIndex:1];
        [self deleteDirectory:deletionPath];
        query = [@"" stringByAppendingFormat:@"DELETE FROM content WHERE title = '%@'", title];
        [self executeDBStatement:newFilePath withQuery:query];
        query = [@"" stringByAppendingFormat:@"DELETE FROM content_search WHERE pack = '%@'", title];
        [self executeDBStatement:newFilePath withQuery:query];
    }
    [results dealloc];
}

// Perform local search
-(void)searchLocally:(NSMutableArray*)paramArray withDict:(NSMutableDictionary*)options  {
    NSString *callback = [paramArray pop];    
    NSString *searchTerms = [paramArray objectAtIndex:0];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [paths objectAtIndex:0];
    NSError *error;
    searchTerms = [searchTerms stringByReplacingOccurrencesOfString:@" AND " withString:@" "];
    NSString *dbPath = [documentsDirectory stringByAppendingPathComponent:@"content.db"];
    NSString *stopwordsFile = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"stopwords.txt" ];
    NSString *filesContent = [[NSString alloc] initWithContentsOfFile:stopwordsFile encoding:NSUTF8StringEncoding error:&error];
    NSArray* words = [filesContent componentsSeparatedByString:@","];
    for (int i = 0 ; i < [words count]; i++){
        NSString *term = [@"" stringByAppendingFormat:@" %@ ",[words objectAtIndex:i]];
        searchTerms = [searchTerms stringByReplacingOccurrencesOfString:term  withString:@" "];
    }

    NSString *query = @"SELECT pack, section, path FROM content_search, content WHERE content MATCH ? and content.title = content_search.pack ORDER BY pack";
    NSArray *args = [NSArray arrayWithObject:searchTerms];
    if ( [paramArray count] > 1){
        query =  @"SELECT pack, section, path FROM content_search, content WHERE content MATCH ? and content.title = content_search.pack and content.title = ? ORDER BY pack";
        args = [NSArray arrayWithObjects:searchTerms,[paramArray objectAtIndex:1], nil];
    }
    
    NSMutableArray *results = [self readFromDatabase:dbPath withQuery:query withArguments:args];
    NSMutableArray *allResults = [[NSMutableArray alloc] init];
    NSString *pack = nil;
    NSMutableArray *sections = [[NSMutableArray alloc] init];
    NSMutableArray *dataRow = [[NSMutableArray alloc] initWithCapacity:3];
    for (int i = 0 ; i < [results count]; i++) {
        if (pack != nil && ![pack isEqualToString:[[results objectAtIndex:i] objectAtIndex:0]]){
            [dataRow addObject:[[results objectAtIndex:i-1] objectAtIndex:0]];
            [dataRow addObject:[[results objectAtIndex:i-1] objectAtIndex:2]];
            [dataRow addObject:sections];
            [allResults addObject:dataRow];
            [sections release];
            sections = [[NSMutableArray alloc] init];
            [dataRow release];
            dataRow = [[NSMutableArray alloc] initWithCapacity:3];
            
        } 
        pack = [[results objectAtIndex:i] objectAtIndex:0];
        [sections addObject:[[results objectAtIndex:i] objectAtIndex:1]];
        
    }
    if ([results count] > 0) {
        [dataRow addObject:[[results objectAtIndex:[results count]-1] objectAtIndex:0]];
        [dataRow addObject:[[results objectAtIndex:[results count]-1] objectAtIndex:2]];
        [dataRow addObject:sections];
        [allResults addObject:dataRow];
    }
    [sections release];
    [dataRow release];
    NSMutableDictionary *resultList = [NSMutableDictionary dictionaryWithCapacity:0];
    [resultList setObject:allResults forKey:@"rows"];
    NSString *jsonStr = [@"" stringByAppendingString:[resultList JSONString]];
    [results dealloc];
    [allResults release];

    [self sendCallbackData:callback withData:jsonStr isSuccess:true];

}



//
// send callback data
//
-(void) sendCallbackData:(NSString*) callback withData:(NSString*)data isSuccess:(BOOL)success {
    CDVPluginResult *pR = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:data];
    if (success)
        [self writeJavascript:[pR toSuccessCallbackString:callback]];
    else 
        [self writeJavascript:[pR toErrorCallbackString:callback]];
}

// Retrieve all currently installed content packs
-(void) getCurrentContentList:(NSMutableArray*)paramArray withDict:(NSMutableDictionary*)options  {
    NSString *callback = [paramArray pop];
    NSString *query = [@"" stringByAppendingFormat:@"SELECT * FROM content "];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [paths objectAtIndex:0];	
	
	NSString *newFilePath = [documentsDirectory stringByAppendingPathComponent:@"content.db"];
    NSMutableArray *results = [self readFromDatabase:newFilePath withQuery:query withArguments:nil];
    NSMutableDictionary *resultList = [NSMutableDictionary dictionaryWithCapacity:0];
    [resultList setObject:results forKey:@"rows"];
    NSString *jsonStr = [resultList JSONString];

    [self sendCallbackData:callback withData:jsonStr isSuccess:true];
    [self sendCallbackData:callback withData:@""  isSuccess:true];
   
}


// call to execute the download in a background thread
-(void) downloadFile:(NSMutableArray*)paramArray
{
	[self performSelectorInBackground: @selector( downloadInBackground: ) withObject: paramArray ];
}

// call to unzip downloaded content in a background thread
-(void) unzipDownload:(NSMutableArray*)paramArray
{
	[self performSelectorInBackground: @selector( unzipInBackground: ) withObject: paramArray ];
}

// perform actual unzip and return callback to main thread
-(void) unzipInBackground:(NSMutableArray*)paramArray
{
    NSString * fileName = [paramArray objectAtIndex:0];
    NSString * title = [paramArray objectAtIndex:1];
    NSString * version = [paramArray objectAtIndex:2];
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString * newFilePath = [self unzipFile:fileName withTitle:title withVersion:version];
    if (newFilePath == nil) {
        [self performSelectorOnMainThread:@selector(downloadCompleteWithError:)
                               withObject:@"Unzip failed"  waitUntilDone:YES];
        self.downloadLocked = false;
        [pool drain];
        return;
    }
    [self performSelectorOnMainThread:@selector(downloadComplete:)
                           withObject:newFilePath waitUntilDone:YES];
    [pool drain];
}


// downloads  in the background and saves it to the local documents
// directory 
-(void) downloadInBackground:(NSMutableArray*)paramArray
{
	NSString * sourceUrl = [paramArray objectAtIndex:0];
	NSString * fileName = [paramArray objectAtIndex:1];
    NSString * title = [paramArray objectAtIndex:2];
    NSString * version = [paramArray objectAtIndex:3];
    NSString *wantUnzip = [paramArray objectAtIndex:4];
    NSString *errorDesc = @"";
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSData* theData = [NSData dataWithContentsOfURL: [NSURL URLWithString:sourceUrl] ];
	if (theData == NULL) {
        errorDesc = [errorDesc stringByAppendingString:@"Source file on server not found. Contact packet maintainer."];
        [self performSelectorOnMainThread:@selector(downloadCompleteWithError:)
                               withObject:errorDesc waitUntilDone:YES];

    } else {
        // save file in documents directory
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];	
	
        NSString *newFilePath = [documentsDirectory stringByAppendingPathComponent:fileName];
	
        NSError *error=[[[NSError alloc]init] autorelease]; 
    
        BOOL response = [theData writeToFile:newFilePath options:NSDataWritingFileProtectionNone error:&error];
        if ( response == NO ) {
            errorDesc = [errorDesc stringByAppendingString:[error description]];
        
            // send our results back to the main thread
            [self performSelectorOnMainThread:@selector(downloadCompleteWithError:)
                               withObject:errorDesc waitUntilDone:YES];
        
        } else {
            if (wantUnzip.boolValue) {
                NSLog(@"Unzipping file");
                newFilePath = [self unzipFile:newFilePath withTitle:title withVersion:version];
                if (newFilePath == nil) {
                    [self performSelectorOnMainThread:@selector(downloadCompleteWithError:)
                                           withObject:@"Unzip failed"  waitUntilDone:YES];
                    self.downloadLocked = false;
                    [pool drain];
                    return;
                }
            } 
            // send our results back to the main thread  
            [self performSelectorOnMainThread:@selector(downloadComplete:)
                                   withObject:newFilePath waitUntilDone:YES];
        
        }
    }
    self.downloadLocked = false;
    [pool drain];
	
}

// calls the predefined callback in the ui to indicate download completion
-(void) downloadComplete:(id)object {
    NSString *jsCallBack = (NSString*)object;
    [self sendCallbackData:[self callbackId] withData:jsCallBack isSuccess:true];
}

// calls the predefined callback in the ui to indicate download error
-(void) downloadCompleteWithError:(NSString *)errorStr  {
    [self sendCallbackData:[self callbackId] withData:errorStr isSuccess:false];
}

// release pool
- (void)dealloc{
	if (params) {
		[params release];
	}
    [super dealloc];
}

// unzip operation + install content pack
-(NSString*) unzipFile:(NSString *)fileName withTitle:(NSString*)title withVersion:(NSString*)version {
    NSMutableString *dirName = [@"" mutableCopy];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [paths objectAtIndex:0];	
    NSString *componentsDirectory = [documentsDirectory stringByAppendingPathComponent:@"Content"];
    NSString *newLocalPath = nil;

    BOOL ret = NO;
    ZipArchive *zipFile = [[ZipArchive alloc] init];
    if ([ zipFile UnzipOpenFile: fileName ]) {
        ret = [zipFile UnzipFileTo: componentsDirectory overWrite: YES unzippedDirectory:dirName];  
        [zipFile UnzipCloseFile];
    } 
    if (ret) {
        [self deleteFile:fileName];
        NSString *dbPath = [documentsDirectory stringByAppendingPathComponent:@"content.db"];
        NSString *dir = [dirName  substringToIndex:[dirName length]-1];
        newLocalPath = [@"" stringByAppendingFormat:@"%@/Content/%@", documentsDirectory, dir ];
        
        NSString *query = [@"" stringByAppendingFormat:@"INSERT INTO content VALUES ('%@', '%@', '', '', '%@')", title, newLocalPath, version];
        BOOL result = [self executeDBStatement:dbPath withQuery:query];  
        NSString *originDB = [newLocalPath stringByAppendingPathComponent:@"search.db"];
        if (!result)
            newLocalPath = nil;
        else {
            [self importSearchIndex:dbPath withOrigin:originDB];
        }
    }
    [zipFile release];
    [dirName release];
    return newLocalPath;
}

// delete file at path
-(BOOL) deleteFile:(NSString*)path {
	NSError *error;
    //Does file exist ?
	if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        //Delete it
		if (![[NSFileManager defaultManager] 
              removeItemAtPath:path error:&error]){
            return NO;
		}
	} else {
        return NO;
    }
    return YES;
}

// delete directory at path
-(BOOL) deleteDirectory:(NSString*)path {
    NSError *error;	
        //Does directory exist?
	if ([[NSFileManager defaultManager] fileExistsAtPath:path])	{
            //Delete it
		if (![[NSFileManager defaultManager] 
                    removeItemAtPath:path error:&error]) {
            return NO;
		}
	} else {
        return NO;
    }
    return YES;
}

// initialize, i.e. open database and create tables if necessary
-(BOOL) initDB {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [paths objectAtIndex:0];	
    NSString *dbPath = [documentsDirectory stringByAppendingPathComponent:@"content.db"];
    BOOL result = false;
    if (![[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
        NSString *query = @"CREATE TABLE content (title text, path text, created text, partOfProgram text, version text)";
        result = [self executeDBStatement:dbPath withQuery:query];
        query = @"CREATE VIRTUAL TABLE content_search using FTS3(pack,section,content,tokenize=porter)";
        result = [self executeDBStatement:dbPath withQuery:query];
	}
     
    return result;
}

// execute database statement
-(BOOL) executeDBStatement: (NSString*)databasePath withQuery: (NSString*)query {
    sqlite3 *database;
    char *errMsg;
    BOOL result = false;
    const char* sqlStatement = [query UTF8String];
    if(sqlite3_open([databasePath UTF8String], &database) == SQLITE_OK) {
        if (sqlite3_exec(database, sqlStatement, NULL, NULL, &errMsg) == SQLITE_OK) {
            result = true;
        } else {
            NSString *bar = [NSString stringWithCString:errMsg encoding:NSUTF8StringEncoding];
            NSLog(@"Errors when executing DB statement: %@ ", bar);
        }
        sqlite3_close(database);
    }
    return result;
}

// import search index from just installed content pack
-(void) importSearchIndex: (NSString*)databasePath withOrigin:(NSString*)path {
    sqlite3 *databaseOrigin, *database;
    const char *query = "SELECT pack, section, content from content_search";
    const char *insert = "INSERT INTO content_search(pack, section, content) VALUES (?,?,?)";
    if(sqlite3_open([path UTF8String], &databaseOrigin) == SQLITE_OK) {
        if(sqlite3_open([databasePath UTF8String], &database) == SQLITE_OK) {
            sqlite3_stmt *compiledStatement, *insertStatement;
            if(sqlite3_prepare_v2(databaseOrigin, query, -1, &compiledStatement, NULL) == SQLITE_OK) {
                while(sqlite3_step(compiledStatement) == SQLITE_ROW) {
                    char *pack = (char *)sqlite3_column_text(compiledStatement, 0);
                    char *section = (char *)sqlite3_column_text(compiledStatement, 1);
                    char *content = (char *)sqlite3_column_text(compiledStatement, 2);
                    if(sqlite3_prepare_v2(database, insert, -1, &insertStatement, NULL) == SQLITE_OK) {
                        sqlite3_bind_text(insertStatement, 1, pack, -1, SQLITE_TRANSIENT);
                        sqlite3_bind_text(insertStatement, 2, section, -1, SQLITE_TRANSIENT);
                        sqlite3_bind_text(insertStatement, 3, content, -1, SQLITE_TRANSIENT);
                        sqlite3_step(insertStatement);
                        sqlite3_finalize(insertStatement); 
                    }
                }
                sqlite3_finalize(compiledStatement); 
            }
            sqlite3_close(database);
        }
        sqlite3_close(databaseOrigin);
    }
}

// read data from database according to query
-(NSMutableArray*) readFromDatabase: (NSString*)databasePath withQuery: (NSString*)query withArguments:(NSArray*)args {
	sqlite3 *database;
    
	// Init the data Array
	NSMutableArray *data = [[NSMutableArray alloc] init];
    
	// Open the database from the users filessytem
	if(sqlite3_open([databasePath UTF8String], &database) == SQLITE_OK) {
		// Setup the SQL Statement and compile it for faster access
		sqlite3_stmt *compiledStatement;
        const char* sqlStatement = [query UTF8String];
		if(sqlite3_prepare_v2(database, sqlStatement, -1, &compiledStatement, NULL) == SQLITE_OK) {
            if (args != nil) {
                for (int i = 0; i < [args count]; i++){
                    sqlite3_bind_text(compiledStatement, i+1, [[args objectAtIndex:i] UTF8String], -1, SQLITE_TRANSIENT);
                }
            } 
			// Loop through the results and add them to the feeds array
			while(sqlite3_step(compiledStatement) == SQLITE_ROW) {
				// Read the data from the result row
                int numberOfCols = sqlite3_column_count(compiledStatement);
                NSMutableArray *entry = [[NSMutableArray alloc] initWithCapacity:numberOfCols+2];
                for (int i = 0; i < numberOfCols; i++){
                    NSString *data = [NSString stringWithUTF8String:(char *)sqlite3_column_text(compiledStatement, i)];
                    [entry addObject:data];
                }

				// Add the object to the array
				[data addObject:entry];
				[entry release];
			}
		} 
        
		// Release the compiled statement from memory
		sqlite3_finalize(compiledStatement);   
	} 
	sqlite3_close(database);
    return data;
}


@end
