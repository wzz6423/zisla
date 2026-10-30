public enum RecordingLivePhotoPolicy {
    public static let maximumDuration = 3.0

    public static func supports(duration: Double) -> Bool {
        duration > 0 && duration <= maximumDuration
    }
}
