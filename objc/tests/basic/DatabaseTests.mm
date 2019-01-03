/*
 * Tencent is pleased to support the open source community by making
 * WCDB available.
 *
 * Copyright (C) 2017 THL A29 Limited, a Tencent company.
 * All rights reserved.
 *
 * Licensed under the BSD 3-Clause License (the "License"); you may not use
 * this file except in compliance with the License. You may obtain a copy of
 * the License at
 *
 *       https://opensource.org/licenses/BSD-3-Clause
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "DatabaseTestCase.h"

@interface DatabaseTests : DatabaseTestCase

@end

@implementation DatabaseTests

- (void)test_tag
{
    TestCaseAssertNotEqual(self.database.tag, WCTInvalidTag);
    WCTDatabase* another = [[WCTDatabase alloc] initWithPath:self.path];
    TestCaseAssertEqual(self.database.tag, another.tag);
}

- (void)test_path
{
    TestCaseAssertTrue([self.database.path isEqualToString:self.path]);
}

- (void)test_existing
{
    WCTTag tag = self.database.tag;
    {
        WCTDatabase* existing = [[WCTDatabase alloc] initWithExistingDatabaseByPath:self.path];
        TestCaseAssertTrue(existing != nil);
        TestCaseAssertEqual(tag, existing.tag);
        [existing invalidate];
    }
    {
        WCTDatabase* existing = [[WCTDatabase alloc] initWithExistingDatabaseByTag:self.database.tag];
        TestCaseAssertTrue(existing != nil);
        TestCaseAssertEqual(tag, existing.tag);
        [existing invalidate];
    }
    [self.database invalidate];
    {
        WCTDatabase* existing = [[WCTDatabase alloc] initWithExistingDatabaseByPath:self.path];
        TestCaseAssertTrue(existing == nil);
    }
    {
        WCTDatabase* existing = [[WCTDatabase alloc] initWithExistingDatabaseByTag:tag];
        TestCaseAssertTrue(existing == nil);
    }
}

- (void)test_open_and_close
{
    TestCaseAssertFalse([self.database isOpened]);
    TestCaseAssertTrue([self.database canOpen]);
    TestCaseAssertTrue([self.database isOpened]);
    [self.database close];
    TestCaseAssertFalse([self.database isOpened]);
}

- (void)test_feature_close_will_not_checkpoint
{
    TestCaseAssertTrue([self.database canOpen]);
    TestCaseAssertTrue([self.database execute:WCDB::StatementPragma().pragma(WCDB::Pragma::userVersion()).to(1)]);
    TestCaseAssertTrue([self.fileManager fileExistsAtPath:self.walPath]);
    [self.database close];
    TestCaseAssertTrue([self.fileManager fileExistsAtPath:self.walPath]);
}

- (void)test_blockade
{
    [self.database blockade];
    __block NSDate* subthread;
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        TestCaseAssertTrue([self.database canOpen]);
        subthread = [NSDate date];
    });
    [NSThread sleepForTimeInterval:1];
    NSDate* main = [NSDate date];
    [self.database unblockade];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    TestCaseAssertTrue([main compare:subthread] == NSOrderedAscending);
}

- (void)test_blockaded_close
{
    __block NSDate* main;
    __block NSDate* subthread;
    dispatch_group_t group = dispatch_group_create();
    [self.database close:^{
        dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            TestCaseAssertTrue([self.database canOpen]);
            subthread = [NSDate date];
        });
        [NSThread sleepForTimeInterval:1];
        main = [NSDate date];
    }];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    TestCaseAssertTrue([main compare:subthread] == NSOrderedAscending);
}

- (void)test_readonly
{
    NSString* tableName = @"testTable";

    TestCaseObject* object = [[TestCaseObject alloc] init];
    object.isAutoIncrement = YES;
    object.content = self.random.string;

    TestCaseAssertTrue([self.database createTableAndIndexes:tableName withClass:TestCaseObject.class]);
    TestCaseAssertTrue([self.database insertObject:object intoTable:tableName]);

    [self.database close:^{
        for (NSString* path in self.database.paths) {
            if ([self.fileManager fileExistsAtPath:path]) {
                TestCaseAssertTrue([self.fileManager setAttributes:@{NSFileImmutable : @(YES)} ofItemAtPath:path error:nil]);
            }
        }
    }];

    TestCaseAssertTrue([self.database canOpen]);
    TestCaseAssertTrue([self.database getObjectOfClass:TestCaseObject.class fromTable:tableName] != nil);
    TestCaseAssertFalse([self.database insertObject:object intoTable:tableName]);

    // reset attribute
    for (NSString* path in self.database.paths) {
        if ([self.fileManager fileExistsAtPath:path]) {
            TestCaseAssertTrue([self.fileManager setAttributes:@{NSFileImmutable : @(NO)} ofItemAtPath:path error:nil]);
        }
    }
}

@end
