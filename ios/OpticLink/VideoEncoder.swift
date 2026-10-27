import Foundation
import VideoToolbox
import CoreMedia

public protocol VideoEncoderDelegate: AnyObject {
    func didEncodeH264Data(_ data: Data, isKeyFrame: Bool)
}

public class VideoEncoder {
    public weak var delegate: VideoEncoderDelegate?
    
    private var compressionSession: VTCompressionSession?
    private let width: Int32
    private let height: Int32
    private let fps: Int32
    private let bitrate: Int32
    
    public init(width: Int32 = 1920, height: Int32 = 1080, fps: Int32 = 30, bitrate: Int32 = 4_000_000) {
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrate = bitrate
        setupSession()
    }
    
    deinit {
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
        }
    }
    
    private func setupSession() {
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: compressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &compressionSession
        )
        
        guard status == noErr, let session = compressionSession else {
            print("OpticLink: Falló la creación de VTCompressionSession: \(status)")
            return
        }
        
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: (fps * 2) as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        
        VTCompressionSessionPrepareToEncodeFrames(session)
    }
    
    public func encode(sampleBuffer: CMSampleBuffer) {
        guard let session = compressionSession,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: imageBuffer,
            presentationTimeStamp: pts,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }
}

private func compressionOutputCallback(
    outputCallbackRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTEncodeInfoFlags,
    sampleBuffer: CMSampleBuffer?
) {
    guard status == noErr, let sampleBuffer = sampleBuffer, let refCon = outputCallbackRefCon else { return }
    let encoder = Unmanaged<VideoEncoder>.fromOpaque(refCon).takeUnretainedValue()
    
    let isKeyFrame: Bool
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
       let first = attachments.first {
        let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        isKeyFrame = !notSync
    } else {
        isKeyFrame = false
    }
    
    var packetData = Data()
    let startCode = Data([0x00, 0x00, 0x00, 0x01])
    
    // Si es fotograma clave (IDR), extraemos y anteponemos los parámetros SPS y PPS
    if isKeyFrame, let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
        var spsCount = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &spsCount, nalUnitHeaderLengthOut: nil)
        
        for i in 0..<spsCount {
            var paramSetPointer: UnsafePointer<UInt8>?
            var paramSetLength: Int = 0
            if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDesc,
                parameterSetIndex: i,
                parameterSetPointerOut: &paramSetPointer,
                parameterSetSizeOut: &paramSetLength,
                parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil
            ) == noErr, let pointer = paramSetPointer {
                packetData.append(startCode)
                packetData.append(pointer, count: paramSetLength)
            }
        }
    }
    
    guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
    var totalLength: Int = 0
    var dataPointer: UnsafeMutablePointer<Int8>?
    
    if CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer) == noErr,
       let basePointer = dataPointer {
        
        var bufferOffset = 0
        let avcCHeaderLength = 4
        
        while bufferOffset < totalLength - avcCHeaderLength {
            var naluLength: UInt32 = 0
            memcpy(&naluLength, basePointer + bufferOffset, sizeof(UInt32.self))
            naluLength = CFSwapInt32BigToHost(naluLength)
            
            packetData.append(startCode)
            packetData.append(UnsafeRawPointer(basePointer + bufferOffset + avcCHeaderLength).assumingMemoryBound(to: UInt8.self), count: Int(naluLength))
            
            bufferOffset += avcCHeaderLength + Int(naluLength)
        }
    }
    
    if !packetData.isEmpty {
        encoder.delegate?.didEncodeH264Data(packetData, isKeyFrame: isKeyFrame)
    }
}
