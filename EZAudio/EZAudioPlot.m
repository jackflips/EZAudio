//
//  EZAudioPlot.m
//  EZAudio
//
//  Created by Syed Haris Ali on 9/2/13.
//  Copyright (c) 2013 Syed Haris Ali. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "EZAudioPlot.h"
#import <UIKit/UIKit.h>

#import "EZAudio.h"

@interface EZAudioPlot () {
    //  BOOL             _hasData;
    //  TPCircularBuffer _historyBuffer;
    
    // Rolling History
    BOOL    _setMaxLength;
    float   *_scrollHistory;
    int     _scrollHistoryIndex;
    UInt32  _scrollHistoryLength;
    BOOL    _changingHistorySize;
    
    //Rolling History Blocks
    float blockAverage;
    float blockTotal;
    int blockWidth;
    int blockSpacing;
    int virtualScrollHistoryIndex;
    int numSamplesPerPixel;
}
@end

@implementation EZAudioPlot
@synthesize backgroundColor = _backgroundColor;
@synthesize color           = _color;
@synthesize progressColor   = _progressColor;
@synthesize gain            = _gain;
@synthesize plotType        = _plotType;
@synthesize shouldFill      = _shouldFill;
@synthesize shouldMirror    = _shouldMirror;

#pragma mark - Initialization
-(id)init {
    self = [super init];
    if(self){
        [self initPlot];
    }
    return self;
}

-(id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if(self){
        [self initPlot];
    }
    return self;
}

#if TARGET_OS_IPHONE
-(id)initWithFrame:(CGRect)frameRect {
#elif TARGET_OS_MAC
    -(id)initWithFrame:(NSRect)frameRect {
#endif
        self = [super initWithFrame:frameRect];
        if(self){
            [self initPlot];
        }
        return self;
    }
    
    -(void)initPlot {
#if TARGET_OS_IPHONE
        self.backgroundColor = [UIColor blackColor];
        self.color           = [UIColor whiteColor];
#elif TARGET_OS_MAC
        self.backgroundColor = [NSColor blackColor];
        self.color           = [NSColor colorWithCalibratedHue:0 saturation:1.0 brightness:1.0 alpha:1.0];
#endif
        self.gain            = 1.0;
        self.plotType        = EZPlotTypeRolling;
        self.shouldMirror    = NO;
        self.shouldFill      = NO;
        plotData             = NULL;
        nonProgressPlotData     = NULL;
        blockTotal           = 0;
        blockWidth           = 10;
        blockSpacing         = 6;
        numSamplesPerPixel   = 3;
        virtualScrollHistoryIndex = 0;
        _scrollHistory       = NULL;
        _scrollHistoryLength = kEZAudioPlotDefaultHistoryBufferLength;
    }
    
#pragma mark - Setters
    -(void)setBackgroundColor:(id)backgroundColor {
        _backgroundColor = backgroundColor;
        [self _refreshDisplay];
    }
    
    -(void)setColor:(id)color {
        _color = color;
        [self _refreshDisplay];
    }
    
    - (void)setProgressColor:(id)progressColor {
        _progressColor = progressColor;
        [self _refreshDisplay];
    }
    
    -(void)setGain:(float)gain {
        _gain = gain;
        [self _refreshDisplay];
    }
    
    -(void)setPlotType:(EZPlotType)plotType {
        _plotType = plotType;
        [self _refreshDisplay];
    }
    
    -(void)setShouldFill:(BOOL)shouldFill {
        _shouldFill = shouldFill;
        [self _refreshDisplay];
    }
    
    -(void)setShouldMirror:(BOOL)shouldMirror {
        _shouldMirror = shouldMirror;
        [self _refreshDisplay];
    }
    
    -(void)_refreshDisplay {
#if TARGET_OS_IPHONE
        [self setNeedsDisplay];
#elif TARGET_OS_MAC
        [self setNeedsDisplay:YES];
#endif
    }
    
#pragma mark - Get Data
    -(void)setSampleData:(float *)data
length:(int)length {
    if( plotData != nil ){
        free(plotData);
    }
    
    plotData   = (CGPoint *)calloc(sizeof(CGPoint),length);
    plotLength = length;
    
    for(int i = 0; i < length; i++) {
        data[i]     = i == 0 ? 0 : data[i];
        plotData[i] = CGPointMake(i,data[i] * _gain);
    }
    
    [self _refreshDisplay];
}
    
#pragma mark - Update
    -(void)updateBuffer:(float *)buffer withBufferSize:(UInt32)bufferSize {
        if( _plotType == EZPlotTypeRolling ) {
            for (int a=0; a<numSamplesPerPixel; a++) {
                // Update the scroll history datasource
                [EZAudio updateScrollHistory:&_scrollHistory
                                  withLength:_scrollHistoryLength
                                     atIndex:&_scrollHistoryIndex
                                  withBuffer:buffer
                              withBufferSize:bufferSize
                        isResolutionChanging:&_changingHistorySize];
                
                [self setSampleData:_scrollHistory
                             length:(!_setMaxLength?kEZAudioPlotMaxHistoryBufferLength:_scrollHistoryLength)];
                _setMaxLength = YES;
            }
        }
        else if ( _plotType == EZPlotTypeRollingBlocks || _plotType == EZPlotTypeRollingBlocksScrollRightPlot) {
            
            //add a new function to separate the data into discrete blocks and also a way to change the scroll direction.
            for (int a=0; a<numSamplesPerPixel; a++) {
                [EZAudio updateScrollHistory:&_scrollHistory
                                  withLength:_scrollHistoryLength
                                     atIndex:&_scrollHistoryIndex
                                  withBuffer:buffer
                              withBufferSize:bufferSize
                        isResolutionChanging:&_changingHistorySize];
                
                virtualScrollHistoryIndex++;
                blockTotal += _scrollHistory[_scrollHistoryIndex-1];
                _scrollHistory[_scrollHistoryIndex-1] = 0;
                if (virtualScrollHistoryIndex % (blockWidth+blockSpacing) == 0) {
                    blockAverage = blockTotal / (blockWidth+blockSpacing);
                    blockTotal = 0;
                }
                
                if (_scrollHistoryIndex > (blockWidth+blockSpacing)) {
                    if (virtualScrollHistoryIndex % (blockWidth+blockSpacing) < blockWidth) {
                        _scrollHistory[MIN(_scrollHistoryIndex-1, virtualScrollHistoryIndex-1)] = MAX(blockAverage*2, .002);
                    } else {
                        _scrollHistory[_scrollHistoryIndex-(blockWidth+blockSpacing)] = 0;
                    }
                }
                
                [self setSampleData:_scrollHistory
                             length:(!_setMaxLength?kEZAudioPlotMaxHistoryBufferLength:_scrollHistoryLength)];
                _setMaxLength = YES;
                
            }
            
        }
        else if( _plotType == EZPlotTypeBuffer ){
            
            [self setSampleData:buffer
                         length:bufferSize];
            
        }
        else {
            
            // Unknown plot type
            
        }
    }
    
#if TARGET_OS_IPHONE
    - (void)drawRect:(CGRect)rect
    {
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        CGContextSaveGState(ctx);
        CGRect frame = self.bounds;
#elif TARGET_OS_MAC
        - (void)drawRect:(NSRect)dirtyRect
        {
            [[NSGraphicsContext currentContext] saveGraphicsState];
            NSGraphicsContext * nsGraphicsContext = [NSGraphicsContext currentContext];
            CGContextRef ctx = (CGContextRef) [nsGraphicsContext graphicsPort];
            NSRect frame = self.bounds;
#endif
            
#if TARGET_OS_IPHONE
            // Set the background color
            [(UIColor*)self.backgroundColor set];
            UIRectFill(frame);
            // Set the waveform line color
            [(UIColor*)self.color set];
#elif TARGET_OS_MAC
            [(NSColor*)self.backgroundColor set];
            NSRectFill(frame);
            [(NSColor*)self.color set];
#endif
            
            if(plotLength > 0) {
                plotData[plotLength-1] = CGPointMake(plotLength-1,0.0f);
                if (self.progress > 0) {
                    [self draw:ctx progress:YES];
                }
                if (self.progress < 1) {
                    [self draw:ctx progress:NO];
                }
            }
#if TARGET_OS_IPHONE
            CGContextRestoreGState(ctx);
#elif TARGET_OS_MAC
            [[NSGraphicsContext currentContext] restoreGraphicsState];
#endif
        }
        
        - (void)draw:(CGContextRef)ctx progress:(BOOL)progress {
            CGRect frame = self.bounds;
            CGMutablePathRef halfPath = CGPathCreateMutable();
            if (progress) {
                int plotLengthProgress = floor(self.progress*plotLength);
                plotData[plotLengthProgress-1] = CGPointMake(plotLengthProgress-1,0.0f);
                if (_plotType == EZPlotTypeRollingBlocksScrollRightPlot) {
                    NSLog(@"ok");
                    for (int i=0; i<plotLengthProgress; i++) {
                        plotData[i].x = abs(plotData[i].x - (plotLength/2)) + (plotLength/2);
                    }
                }
                CGPathAddLines(halfPath,
                               NULL,
                               plotData,
                               plotLengthProgress);
            } else {
                
                int nonProgressPortion = ceil(plotLength*self.progress);
                int nonProgressPortionLength = plotLength-nonProgressPortion;
                plotData[nonProgressPortion-1] = CGPointMake(nonProgressPortion-1,0.0f);
                free(nonProgressPlotData);
                nonProgressPlotData = (CGPoint *)calloc(sizeof(CGPoint), nonProgressPortionLength);
                for(int i=0;i<nonProgressPortionLength;i++) {
                    nonProgressPlotData[i].x = plotData[i+nonProgressPortion].x;
                    nonProgressPlotData[i].y = plotData[i+nonProgressPortion].y;
                }
                nonProgressPlotData[0] = CGPointMake(nonProgressPortion, 0);
                if (_plotType == EZPlotTypeRollingBlocksScrollRightPlot) {
                    for (int i=0; i<nonProgressPortionLength; i++) {
                        nonProgressPlotData[i].x = abs((nonProgressPlotData[i].x - plotLength/2) - plotLength/2);
                    }
                }
                CGPathAddLines(halfPath,
                               NULL,
                               nonProgressPlotData,
                               nonProgressPortionLength);
            }
            CGMutablePathRef path = CGPathCreateMutable();
            
            double xscale = (frame.size.width) / (float)plotLength;
            double halfHeight = floor( frame.size.height / 2.0 );
            
            // iOS drawing origin is flipped by default so make sure we account for that
            int deviceOriginFlipped = 1;
#if TARGET_OS_IPHONE
            deviceOriginFlipped = -1;
#elif TARGET_OS_MAC
            deviceOriginFlipped = 1;
#endif
            
            CGAffineTransform xf = CGAffineTransformIdentity;
            xf = CGAffineTransformTranslate( xf, frame.origin.x , halfHeight + frame.origin.y );
            xf = CGAffineTransformScale( xf, xscale, deviceOriginFlipped*halfHeight );
            CGPathAddPath( path, &xf, halfPath );
            
            if( self.shouldMirror ){
                xf = CGAffineTransformIdentity;
                xf = CGAffineTransformTranslate( xf, frame.origin.x , halfHeight + frame.origin.y);
                xf = CGAffineTransformScale( xf, xscale, -deviceOriginFlipped*(halfHeight));
                CGPathAddPath( path, &xf, halfPath );
            }
            CGPathRelease( halfPath );
            
            // Now, path contains the full waveform path.
            CGContextAddPath(ctx, path);
            
            // Make this color customizable
            if( self.shouldFill ){
                if (progress) {
                    CGContextSetFillColorWithColor(ctx, [self.progressColor CGColor]);
                } else {
                    CGContextSetFillColorWithColor(ctx, [self.color CGColor]);
                }
                CGContextFillPath(ctx);
            }
            else {
                CGContextStrokePath(ctx);
            }
            CGPathRelease(path);
        }
        
#pragma mark - Adjust Resolution
        -(int)setRollingHistoryLength:(int)historyLength {
            historyLength = MIN(historyLength,kEZAudioPlotMaxHistoryBufferLength);
            size_t floatByteSize = sizeof(float);
            _changingHistorySize = YES;
            if( _scrollHistoryLength != historyLength ){
                _scrollHistoryLength = historyLength;
            }
            _scrollHistory = realloc(_scrollHistory,_scrollHistoryLength*floatByteSize);
            if( _scrollHistoryIndex < _scrollHistoryLength ){
                memset(&_scrollHistory[_scrollHistoryIndex],
                       0,
                       (_scrollHistoryLength-_scrollHistoryIndex)*floatByteSize);
            }
            else {
                _scrollHistoryIndex = _scrollHistoryLength;
            }
            _changingHistorySize = NO;
            return historyLength;
        }
        
        -(int)rollingHistoryLength {
            return _scrollHistoryLength;
        }
        
        -(void)dealloc {
            if( plotData ){
                free(plotData);
            }
        }
        
        @end
