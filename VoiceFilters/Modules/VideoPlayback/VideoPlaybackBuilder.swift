struct VideoPlaybackBuilder {
    static func build() -> VideoPlaybackViewController {
        let presenter = VideoPlaybackPresenter()
        let vc = VideoPlaybackViewController(presenter: presenter)
        presenter.viewInput = vc
        return vc
    }
}
