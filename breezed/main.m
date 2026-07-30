#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

#define IWIDGETS_PLIST @"/var/mobile/Library/Preferences/iWidgets.plist"
#define IWIDGETS_DIR   @"/var/mobile/Library/iWidgets"
#define BUNDLE_ID      @"com.breeze.daemon"

@interface CLLocationManager (Private)
+ (void)setAuthorizationStatus:(BOOL)status forBundleIdentifier:(NSString *)bundleIdentifier;
- (instancetype)initWithEffectiveBundleIdentifier:(NSString *)bundleIdentifier;
@end

@interface WidgetConfig : NSObject
@property (nonatomic, assign) BOOL isValid;
@property (nonatomic, assign) BOOL isDefaultKey;
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, assign) BOOL useIPLocation;
@property (nonatomic, strong) NSArray *targetWidgetNames;
@end

@implementation WidgetConfig
@end

@interface WeatherDaemon : NSObject <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, assign) BOOL useIPLocation;
@property (nonatomic, strong) NSArray *targetWidgetNames;
@end

@implementation WeatherDaemon

- (instancetype)initWithConfig:(WidgetConfig *)config {
    self = [super init];
    if (self) {
        _apiKey = [config.apiKey copy];
        _useIPLocation = config.useIPLocation;
        _targetWidgetNames = config.targetWidgetNames;
    }
    return self;
}

- (void)start {
    if (self.useIPLocation) {
        NSLog(@"[breezed] Using IP location...");
        [self fetchIPLocation];
    } else {
        NSLog(@"[breezed] Using CoreLocation via Private API...");

        [CLLocationManager setAuthorizationStatus:YES forBundleIdentifier:BUNDLE_ID];

        _locationManager = [[CLLocationManager alloc] initWithEffectiveBundleIdentifier:BUNDLE_ID];
        [_locationManager setDistanceFilter:kCLDistanceFilterNone];
        [_locationManager setDesiredAccuracy:kCLLocationAccuracyKilometer];
        [_locationManager setDelegate:self];
        
        [_locationManager startUpdatingLocation];
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    CLLocation *loc = [locations lastObject];
    [_locationManager stopUpdatingLocation];

    NSLog(@"[breezed] Got CoreLocation coordinates: %f, %f", loc.coordinate.latitude, loc.coordinate.longitude);
    [self fetchWeatherForLat:loc.coordinate.latitude lon:loc.coordinate.longitude locationName:nil];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    NSLog(@"[breezed] CoreLocation error: %@", error);
    [self updateStatusInAllWidgets:[NSString stringWithFormat:@"Error: CoreLocation failed (%@)", error.localizedDescription]];
    exit(1);
}

- (void)fetchIPLocation {
    NSURL *url = [NSURL URLWithString:@"http://ip-api.com/json/?fields=status,country,city,lat,lon"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setTimeoutInterval:10.0];

    [NSURLConnection sendAsynchronousRequest:request
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError || !data) {
            NSLog(@"[breezed] IP Location request failed: %@", connectionError);
            [self updateStatusInAllWidgets:@"Error: IP location failed"];
            exit(1);
        }

        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        if (json && [json[@"status"] isEqualToString:@"success"]) {
            double lat = [json[@"lat"] doubleValue];
            double lon = [json[@"lon"] doubleValue];
            NSString *city = json[@"city"];
            
            NSLog(@"[breezed] Got IP coordinates: %f, %f (%@)", lat, lon, city);
            [self fetchWeatherForLat:lat lon:lon locationName:city];
        } else {
            NSLog(@"[breezed] Invalid IP location JSON payload");
            [self updateStatusInAllWidgets:@"Error: Invalid IP location payload"];
            exit(1);
        }
    }];
}

- (void)fetchWeatherForLat:(double)lat lon:(double)lon locationName:(NSString *)locationName {
    NSString *urlString = [NSString stringWithFormat:@"https://api.weather.yandex.ru/v2/forecast?lat=%f&lon=%f&lang=ru_RU", lat, lon];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    [request setHTTPMethod:@"GET"];
    [request setValue:self.apiKey forHTTPHeaderField:@"X-Yandex-Weather-Key"];
    [request setTimeoutInterval:15.0];

    [NSURLConnection sendAsynchronousRequest:request
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError || !data) {
            NSLog(@"[breezed] Weather network error: %@", connectionError);
            [self updateStatusInAllWidgets:@"Error: Yandex API network failed"];
            exit(1);
        }

        NSError *jsonErr = nil;
        NSMutableDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&jsonErr];
        
        if (!jsonDict || jsonErr) {
            NSLog(@"[breezed] Failed to parse Yandex JSON");
            [self updateStatusInAllWidgets:@"Error: Invalid Yandex API response"];
            exit(1);
        }

        if (locationName && locationName.length > 0) {
            jsonDict[@"locationName"] = locationName;
        }

        NSData *finalJsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];
        NSString *jsonString = [[NSString alloc] initWithData:finalJsonData encoding:NSUTF8StringEncoding];
        NSString *finalJS = [NSString stringWithFormat:@"var weatherData = %@;", jsonString];

        [self writeWeatherJSToAllWidgets:finalJS status:@"OK (Updated successfully)"];
        exit(0);
    }];
}

- (void)writeWeatherJSToAllWidgets:(NSString *)jsContent status:(NSString *)status {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *dateStr = [formatter stringFromDate:[NSDate date]];
    NSString *debugLine = [NSString stringWithFormat:@"\n// Last run: %@ | Status: %@", dateStr, status];
    
    NSString *contentToWrite = [jsContent stringByAppendingString:debugLine];

    for (NSString *widgetName in self.targetWidgetNames) {
        NSString *path = [NSString stringWithFormat:@"%@/%@/weather.js", IWIDGETS_DIR, widgetName];
        NSError *error = nil;
        BOOL success = [contentToWrite writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (success) {
            NSLog(@"[breezed] Successfully updated %@", path);
        } else {
            NSLog(@"[breezed] Failed to write to %@: %@", path, error.localizedDescription);
        }
    }
}

- (void)updateStatusInAllWidgets:(NSString *)status {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *dateStr = [formatter stringFromDate:[NSDate date]];
    NSString *debugLine = [NSString stringWithFormat:@"\n// Last run: %@ | Status: %@", dateStr, status];

    for (NSString *widgetName in self.targetWidgetNames) {
        NSString *path = [NSString stringWithFormat:@"%@/%@/weather.js", IWIDGETS_DIR, widgetName];
        NSError *error = nil;
        NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
        
        if (!content) {
            content = @"var weatherData = {}; // Waiting for first successful download";
        }

        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\n// Last run:.*" options:0 error:nil];
        NSString *cleanContent = [regex stringByReplacingMatchesInString:content options:0 range:NSMakeRange(0, content.length) withTemplate:@""];
        NSString *updatedContent = [cleanContent stringByAppendingString:debugLine];

        [updatedContent writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

@end

WidgetConfig *parseConfigFromPlist(void) {
    WidgetConfig *config = [[WidgetConfig alloc] init];
    config.isValid = NO;
    config.isDefaultKey = YES;
    config.apiKey = @"";
    config.useIPLocation = YES;

    NSArray *plistArray = [NSArray arrayWithContentsOfFile:IWIDGETS_PLIST];
    if (!plistArray) {
        NSLog(@"[breezed] Could not read iWidgets plist at %@", IWIDGETS_PLIST);
        return config;
    }

    NSMutableArray *targets = [NSMutableArray array];
    NSString *validApiKey = nil;
    BOOL ipLoc = YES;

    for (NSDictionary *widget in plistArray) {
        NSString *name = widget[@"name"];
        
        if (name && [name.lowercaseString rangeOfString:@"breeze"].location != NSNotFound) {
            [targets addObject:name];
            
            NSDictionary *options = widget[@"options"];
            if (options) {
                NSString *key = options[@"apiKey"];
                if (key && ![key isEqualToString:@"default"] && key.length > 0) {
                    if (!validApiKey) {
                        validApiKey = key;
                        if (options[@"useIPLocation"] != nil) {
                            ipLoc = [options[@"useIPLocation"] boolValue];
                        }
                    }
                }
            }
        }
    }

    if (targets.count > 0) {
        config.isValid = YES;
        config.targetWidgetNames = targets;
        
        if (validApiKey) {
            config.isDefaultKey = NO;
            config.apiKey = validApiKey;
            config.useIPLocation = ipLoc;
        }
    }

    return config;
}

int main(int argc, char **argv, char **envp) {
    @autoreleasepool {
        WidgetConfig *config = parseConfigFromPlist();

        if (!config.isValid) {
            NSLog(@"[breezed] No active breeze widgets found in iWidgets.plist. Exiting.");
            return 0;
        }

        if (config.isDefaultKey) {
            NSLog(@"[breezed] API_KEY is set to 'default'. Nothing to do.");
            WeatherDaemon *dummy = [[WeatherDaemon alloc] initWithConfig:config];
            [dummy updateStatusInAllWidgets:@"Skipped (API_KEY is default)"];
            return 0;
        }

        NSLog(@"[breezed] Config loaded for widgets: %@. Starting sequence...", [config.targetWidgetNames componentsJoinedByString:@", "]);
        WeatherDaemon *daemon = [[WeatherDaemon alloc] initWithConfig:config];
        [daemon start];

        CFRunLoopRun();
    }
    return 0;
}