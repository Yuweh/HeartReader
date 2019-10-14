//
//  ViewController.m
//  HeartRate_Demo
//
//  Created by Transuner on 16/4/15. < -- just translated for ref // thanks
//  Copyright © 2016年 吴冰. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "PulseDetector.h"
#import "Fiter.h"
@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate>{
    BOOL showText; //自己个性化加个标识 // add their own personalized identity
}
@property(nonatomic, strong) AVCaptureSession *session;
@property(nonatomic, strong) AVCaptureDevice *camera;
@property(nonatomic, strong) PulseDetector *pulseDetector;
@property(nonatomic, strong) Fiter *fiter;
@property(nonatomic, assign) CURRENT_STATE currentState;
@property(nonatomic, assign) int validFrameCounter;

@property (nonatomic, strong) UILabel * PulseRate;
@property (nonatomic, strong) UILabel * ValidFrames;

@end

@implementation ViewController

-(void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self resume];
}

-(void) viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self pause];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.PulseRate = [[UILabel alloc]initWithFrame:(CGRect){0,100,self.view.frame.size.width,200}];
    self.PulseRate.backgroundColor = [UIColor lightGrayColor];
    self.PulseRate.textAlignment = 1;
    self.PulseRate.textColor = [UIColor redColor];
    [self.view addSubview:self.PulseRate];
    
    self.ValidFrames = [[UILabel alloc]initWithFrame:(CGRect){0,self.PulseRate.frame.origin.y+self.PulseRate.frame.size.height,self.view.frame.size.width,100}];
    self.ValidFrames.backgroundColor = [UIColor blackColor];
    self.ValidFrames.textColor = [UIColor whiteColor];
    self.ValidFrames.textAlignment = 1;
    self.ValidFrames.font = [UIFont boldSystemFontOfSize:20];
    [self.view addSubview:self.ValidFrames];
    
    self.fiter = [[Fiter alloc]init];
    
    self.pulseDetector = [[PulseDetector alloc]init];
    
    [self startCameraCapture];

}

//开始捕捉帧 // start capturing frame
- (void) startCameraCapture {
    
    //创建AVCapture // Create AVCapture
    self.session = [[AVCaptureSession alloc]init];
    
    //获得默认摄像头设备 // get the default camera equipment
    self.camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
    //打开手电筒模式——没有它不能检测脉冲 // Open torch mode - no it can not detect a pulse
    if([self.camera isTorchModeSupported:AVCaptureTorchModeOn]) {
        [self.camera lockForConfiguration:nil];
        self.camera.torchMode=AVCaptureTorchModeOn;
        [self.camera unlockForConfiguration];
    }
    
    //创建一个AVCaptureInput摄像头设备 // Create a AVCaptureInput camera equipment
    NSError *error=nil;
    AVCaptureInput* cameraInput = [[AVCaptureDeviceInput alloc] initWithDevice:self.camera error:&error];
    if (cameraInput == nil) {
        NSLog(@"Error to create camera capture:%@",error);
    }
    
    //设置输出 // set the output
    AVCaptureVideoDataOutput* videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    
    //创建一个队列运行捕获 // create a queue run captured
    dispatch_queue_t captureQueue=dispatch_queue_create("captureQueue", NULL);
    
    //设置自己的捕获委托 // set their own commission to capture
    [videoOutput setSampleBufferDelegate:self queue:captureQueue];
    
    //配置的像素格式 // Configure pixel format
    videoOutput.videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA], (id)kCVPixelBufferPixelFormatTypeKey, nil];
    
    //最低可接受的帧率设置为10 fps // minimum acceptable frame rate to 10 fps
    videoOutput.minFrameDuration=CMTimeMake(1, 10);
    
    
    //帧的大小——使用最小的帧(大小可用) // size of the frame - minimum frame (size available)
    [self.session setSessionPreset:AVCaptureSessionPresetLow];
    
    //添加输入和输出 // add an input and output
    [self.session addInput:cameraInput];
    [self.session addOutput:videoOutput];
    
    //启动 //start up
    [self.session startRunning];
    
    //相机状态 // Camera status
    self.currentState=STATE_SAMPLING;
    
    //停止程序 // Stop program
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    //定时器每0.1秒执行一次 // Timer executed once every 0.1 seconds
    [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(update) userInfo:nil repeats:YES];

}

-(void) stopCameraCapture {
    [self.session stopRunning];
    self.session=nil;
}

#pragma mark Pause and Resume of pulse detection
-(void) pause {
    if(self.currentState==STATE_PAUSED) return;
    
    //关掉闪光灯 // Turn off the flash
    if([self.camera isTorchModeSupported:AVCaptureTorchModeOn]) {
        [self.camera lockForConfiguration:nil];
        self.camera.torchMode=AVCaptureTorchModeOff;
        [self.camera unlockForConfiguration];
    }
    self.currentState=STATE_PAUSED;
    
    //程序关掉 或退出后台 // exit the program or turn off the background
    [UIApplication sharedApplication].idleTimerDisabled = NO;
}

-(void) resume {
    if(self.currentState!=STATE_PAUSED) return;
    
    ////关掉闪光灯 //// turn off the flash
    if([self.camera isTorchModeSupported:AVCaptureTorchModeOn]) {
        [self.camera lockForConfiguration:nil];
        self.camera.torchMode=AVCaptureTorchModeOn;
        [self.camera unlockForConfiguration];
    }
    self.currentState=STATE_SAMPLING;
    
    //程序关掉 或退出后台 // exit the program or turn off the background
    [UIApplication sharedApplication].idleTimerDisabled = YES;
}

//网上找的算法 // find online algorithm
void RGBtoHSV( float r, float g, float b, float *h, float *s, float *v ) {
    float min, max, delta;
    min = MIN( r, MIN(g, b ));
    max = MAX( r, MAX(g, b ));
    *v = max;
    delta = max - min;
    if( max != 0 )
        *s = delta / max;
    else {
        // r = g = b = 0
        *s = 0;
        *h = -1;
        return;
    }
    if( r == max )
        *h = ( g - b ) / delta;
    else if( g == max )
        *h=2+(b-r)/delta;
    else
        *h=4+(r-g)/delta;
    *h *= 60;
    if( *h < 0 )
        *h += 360;
}

//处理帧的视频 // processing video frames
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    
    //判断停下来不做任和处理 // judge to stop and do not do any processing
    if(self.currentState==STATE_PAUSED) {
        
        //重置我们的帧计数器 // reset our frame counter
        self.validFrameCounter=0;
        return;
    }
    
    
    //判断获取血液波动在值 || Analyzing fluctuations in blood // Get Value
    if (self.validFrameCounter == 0) {
        
   
        dispatch_async(dispatch_get_main_queue(), ^{
            //回调或者说是通知主线程刷新， // callback or notify the main thread is refreshed,
            self.PulseRate.font = [UIFont boldSystemFontOfSize:23];
            self.PulseRate.text=@"Place your finger on the flash in position";
        });

    } else {
        
        
        //得到的数据(可以用来显示进度条或心电图)******** // get the data (may be used to display a progress bar or electrocardiogram) ********
        NSLog(@"int:%d",self.validFrameCounter);
        //*********
        if (!showText) {
            //通知主线程刷新 // notify the main thread refresh
            dispatch_async(dispatch_get_main_queue(), ^{
                //回调或者说是通知主线程刷新，// callback or notify the main thread is refreshed,
                self.PulseRate.font = [UIFont boldSystemFontOfSize:20];
                self.PulseRate.text = @"Getting, please be patient, please do not put your finger off!";
            });
        }
    }
    
    //图像缓冲区 // image buffer
    CVImageBufferRef cvimgRef = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    //锁定图像缓冲区 Lock image buffer
    CVPixelBufferLockBaseAddress(cvimgRef,0);
    
    //访问数据 Access to data
    size_t width=CVPixelBufferGetWidth(cvimgRef);
    
    size_t height=CVPixelBufferGetHeight(cvimgRef);
    
    //获取图像字节 Acquiring an image bytes
    uint8_t *buf=(uint8_t *) CVPixelBufferGetBaseAddress(cvimgRef);
    
    size_t bprow=CVPixelBufferGetBytesPerRow(cvimgRef);
    
    //平均帧的rgb值 The average value of the rgb frame
    float r=0,g=0,b=0;
    for(int y=0; y<height; y++) {
        for(int x=0; x<width*4; x+=4) {
            b+=buf[x];
            g+=buf[x+1];
            r+=buf[x+2];
        }
        buf+=bprow;
    }
    r/=255*(float) (width*height);
    g/=255*(float) (width*height);
    b/=255*(float) (width*height);
    
    //从rgb转换到hsv colourspace // to convert from rgb hsv colourspace
    float h,s,v;
    
    RGBtoHSV(r, g, b, &h, &s, &v);
    
    //做一个检查,看看一个手指被放置在相机 // do a check to see if a finger is placed in the camera
    if(s>0.5 && v>0.5) {
        
        //增加有效的帧数 // increase the effective number of frames
        self.validFrameCounter++;
        
        //滤波器色调值,滤波器是一个简单的带通滤波器,消除任何直流分量和高频噪音 // tone value filter, the filter is a simple band-pass filter to eliminate high frequency noise and any DC component
        float filtered=[self.fiter processValue:h];
        
        
        if(self.validFrameCounter > MIN_FRAMES_FOR_FILTER_TO_SETTLE) {
            
            //将新值添加到脉冲探测器 // Add a new value into a pulse detector
            [self.pulseDetector addNewValue:filtered atTime:CACurrentMediaTime()];
        }
    } else {
        self.validFrameCounter = 0;
        
        //清晰的脉搏检测器——我们只需要这样做一次 // clear pulse detector - we only need to do this once
        [self.pulseDetector reset];
    }
}

-(void) update {
    
    NSInteger distance =  MIN(100, (100 * self.validFrameCounter)/MIN_FRAMES_FOR_FILTER_TO_SETTLE);
    
    //距离等于100显示加载中 // display 100 a distance equal Loading
    if (distance == 100) showText = NO;
    
    self.ValidFrames.text = [NSString stringWithFormat:@"Distance from the finger flash: %ld%%",distance];
    
    //如果我们停下来然后是无事可做 // If we stop and then nothing
    if(self.currentState==STATE_PAUSED) return;
    
    //得到的平均周期的脉冲重复频率脉冲探测器
    float avePeriod=[self.pulseDetector getAverage];
    
    
    //得到的值（以后处理） // value obtained (after processing)
//    NSLog(@"avePeriod:%f",avePeriod);
    
    if(avePeriod==INVALID_PULSE_PERIOD) {
        
        //没有可用的价值 暂不做处理 后期可能会用到 // no value available temporarily to do post-processing may be used

        
    } else {
        
        showText = YES;//出现心条显示心率值
        
        //有值就展示出来 // show value is out there
        float pulse=60.0/avePeriod;
   
        dispatch_async(dispatch_get_main_queue(), ^{
            //回调或者说是通知主线程刷新，
            self.PulseRate.font = [UIFont boldSystemFontOfSize:60];
            self.PulseRate.text=[NSString stringWithFormat:@"Pulse Rate: %0.0f", pulse];
            //[NSString stringWithFormat:@"Distance from the finger flash: %ld%%",distance];

        });
        
    }
}


@end
