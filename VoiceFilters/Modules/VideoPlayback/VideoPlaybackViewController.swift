import AVKit
import MobileCoreServices
import UIKit

protocol VideoPlaybackViewInput: AnyObject {
    func playVideo(for url: URL)

    func showVideoRecordedAlert(for url: URL)

    func showEditedVideoSavedAlert()

    func showLoadingOverlay(text: String)

    func hideLoadingOverlay()

    func restart()
}

final class VideoPlaybackViewController: AVPlayerViewController {
    init(presenter: VideoPlaybackPresenter) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Cannot be constructed from a nib")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()


        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appMovedToBackground),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appMovedToForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if presenter.selectedVideoURL == nil {
            showAlertSheet()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        [
            filterButtonsStackView,
            controlButtonsStackView,
            shareButtonsStackView,
            loadingOverlayView
        ].forEach {
            view.bringSubviewToFront($0)
        }
    }

    // MARK: - Private

    private let presenter: VideoPlaybackPresenter

    private func showAlertSheet() {
        let alertSheet = UIAlertController(title: "Add video", message: nil, preferredStyle: .actionSheet)
        let cameraAction = UIAlertAction(title: "Make now", style: .default) { [weak self] _ in
            self?.presentPicker(for: .camera)

        }
        let galleryAction = UIAlertAction(title: "Select from gallery", style: .default) { [weak self] _ in
            self?.presentPicker(for: .photoLibrary)
        }
        alertSheet.addAction(cameraAction)
        alertSheet.addAction(galleryAction)
        present(alertSheet, animated: true, completion: nil)
    }

    private func didSelect(voiceFilter: VoiceFilter) {
        presenter.apply(voiceFilter: voiceFilter)
        updateFilterButtonsSelection()
    }

    private func updateFilterButtonsSelection() {
        for (buttonVoiceFilter, button) in voiceFilterButtons {
            button.isSelected = buttonVoiceFilter == presenter.selectedFilter
        }
    }

    private func saveEditedVideo() {
        presenter.saveEditedVideo()
    }

    @objc private func appMovedToBackground() {
        player?.pause()
        presenter.engine?.pause()
        presenter.audioPlayer?.pause()
    }

    @objc private func appMovedToForeground() {
        player?.play()
        do {
            try presenter.engine?.start()
            presenter.audioPlayer?.play()
        } catch {}
    }

    // MARK: - UI

    private let filterButtonsStackView = UIStackView()
    private let shareButtonsStackView = UIStackView()
    private let controlButtonsStackView = UIStackView()
    private var voiceFilterButtons: [VoiceFilter: UIButton] = [:]
    private let loadingOverlayView = UIView()
    private let loadingOverlayLabel = UILabel()

    private func setupUI() {
        showsPlaybackControls = false

        setupFilterButtons()
        setupControlButtons()
        setupShareButtons()

        NSLayoutConstraint.activate([
            filterButtonsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            filterButtonsStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            controlButtonsStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            controlButtonsStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            shareButtonsStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            shareButtonsStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        setupPicker()
        setupLoadingOverlayView()
    }

    private func setupFilterButtons() {
        filterButtonsStackView.axis = .vertical
        filterButtonsStackView.spacing = 16
        filterButtonsStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(filterButtonsStackView)

        let voiceFilters: [VoiceFilter] = [.helium, .alien, .darthVader, .cave, .clear]

        voiceFilters.forEach { voiceFilter in
            let button = makeVoiceFilterButton(for: voiceFilter)
            voiceFilterButtons[voiceFilter] = button
            filterButtonsStackView.addArrangedSubview(button)
        }
    }

    private func setupControlButtons() {
        controlButtonsStackView.axis = .horizontal
        controlButtonsStackView.spacing = 24
        controlButtonsStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlButtonsStackView)

        let downloadButton = UIButton()
        downloadButton.setImage(
            .init(named: "download"),
            for: .normal
        )
        downloadButton.addAction { [weak self] in
            self?.saveEditedVideo()
        }
        controlButtonsStackView.addArrangedSubview(downloadButton)

        let restartButton = UIButton()
        restartButton.setImage(
            .init(named: "restart"),
            for: .normal
        )
        restartButton.addAction { [weak self] in
            self?.presenter.didPressRestart()
        }
        controlButtonsStackView.addArrangedSubview(restartButton)
    }

    private func setupShareButtons() {
        shareButtonsStackView.axis = .vertical
        shareButtonsStackView.spacing = 16
        shareButtonsStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shareButtonsStackView)

        let shareSources: [ShareSource] = [.instagram]

        shareSources.forEach { shareSource in
            let button = makeShareButton(for: shareSource)
            shareButtonsStackView.addArrangedSubview(button)
        }
    }

    private func setupLoadingOverlayView() {
        loadingOverlayView.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        view.addSubview(loadingOverlayView)

        let containerView = UIView()
        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = 12
        containerView.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlayView.addSubview(containerView)

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 40
        stackView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(stackView)

        let activityIndicator = UIActivityIndicatorView()
        if #available(iOS 13.0, *) {
            activityIndicator.style = .large
        }
        activityIndicator.color = .init(
            red: 18 / 255,
            green: 77 / 255,
            blue: 191 / 255,
            alpha: 1
        )
        activityIndicator.startAnimating()
        stackView.addArrangedSubview(activityIndicator)

        loadingOverlayLabel.textColor = .black
        loadingOverlayLabel.font = .systemFont(ofSize: 22, weight: .medium)
        loadingOverlayLabel.textAlignment = .center
        stackView.addArrangedSubview(loadingOverlayLabel)

        loadingOverlayView.pinToSuperview()

        NSLayoutConstraint.activate([
            containerView.widthAnchor.constraint(equalToConstant: 300),
            containerView.heightAnchor.constraint(equalToConstant: 140),
            containerView.centerXAnchor.constraint(equalTo: loadingOverlayView.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: loadingOverlayView.centerYAnchor),

            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20),
        ])
        loadingOverlayView.isHidden = true
    }

    private func image(for voiceFilter: VoiceFilter) -> UIImage? {
        switch voiceFilter {
        case .darthVader:
            return .init(named: "darth_vader")
        case .alien:
            return .init(named: "alien")
        case .helium:
            return .init(named: "helium")
        case .cave:
            return .init(named: "cave")
        case .clear:
            return .init(named: "clear")
        }
    }

    private func image(for shareSource: ShareSource) -> UIImage? {
        switch shareSource {
        case .instagram:
            return .init(named: "instagram")
        }
    }

    private func makeVoiceFilterButton(for voiceFilter: VoiceFilter) -> UIButton {
        let button = UIButton()
        button.setBackgroundImage(
            .init(named: "filter_button_background"),
            for: .normal
        )
        button.setBackgroundImage(
            .init(named: "filter_button_background_selected"),
            for: .selected
        )
        button.setImage(image(for: voiceFilter), for: .normal)
        button.addAction { [weak self] in
            self?.didSelect(voiceFilter: voiceFilter)
        }
        return button
    }

    private func makeShareButton(for source: ShareSource) -> UIButton {
        let button = UIButton()
        button.setImage(image(for: source), for: .normal)
        button.addAction { [weak self] in
            self?.presenter.didPressShareVideo(source: source)
        }
        return button
    }

    // MARK: - Picker

    private let picker = UIImagePickerController()

    private func setupPicker() {
        picker.delegate = self

        picker.videoQuality = .typeHigh
        picker.videoExportPreset = AVAssetExportPresetHEVC1920x1080

        picker.mediaTypes = [kUTTypeMovie as String]

        picker.allowsEditing = true
    }

    private func presentPicker(for sourceType: UIImagePickerController.SourceType) {
        picker.sourceType = sourceType
        present(self.picker, animated: true, completion: nil)
    }
}

extension VideoPlaybackViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        dismiss(animated: true, completion: nil)
        guard let videoURL = info[.mediaURL] as? URL else { return }

        if picker.sourceType == .camera {
            presenter.didRecordVideo(videoURL: videoURL)
        } else {
            presenter.didSelectVideo(videoURL: videoURL)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: true) { [weak self] in
            self?.showAlertSheet()
        }
    }
}

// MARK: - ViewInput

extension VideoPlaybackViewController: VideoPlaybackViewInput {
    func playVideo(for url: URL) {
        player = AVPlayer(url: url)
        player?.isMuted = true
        do {
            try presenter.engine?.start()
            presenter.audioPlayer?.play()
            player?.play()
        } catch {}
    }

    func showVideoRecordedAlert(for videoURL: URL) {
        let alert = UIAlertController(
            title: "Video was recorded",
            message: "Do you want to save the video before editing?",
            preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: "No",
                style: UIAlertAction.Style.destructive,
                handler: { [weak self] _ in
                    self?.presenter.didSaveVideo()
                }
            )
        )
        alert.addAction(
            UIAlertAction(
                title: "Yes",
                style: UIAlertAction.Style.default,
                handler: { [weak self] _ in
                    UISaveVideoAtPathToSavedPhotosAlbum(videoURL.path, self, nil, nil)
                    self?.presenter.didSaveVideo()
                }
            )
        )
        present(alert, animated: true, completion: nil)
    }

    func showEditedVideoSavedAlert() {
        let alert = UIAlertController(
            title: "Video was saved",
            message: "Now you can share it or create a new one",
            preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: "Ok",
                style: UIAlertAction.Style.cancel,
                handler: nil
            )
        )
        present(alert, animated: true, completion: nil)
    }

    func showLoadingOverlay(text: String) {
        player?.pause()
        filterButtonsStackView.isHidden = true
        shareButtonsStackView.isHidden = true
        loadingOverlayLabel.text = text
        loadingOverlayView.isHidden = false
    }

    func hideLoadingOverlay() {
        filterButtonsStackView.isHidden = false
        shareButtonsStackView.isHidden = false
        loadingOverlayView.isHidden = true
    }

    func restart() {
        player = nil
        updateFilterButtonsSelection()
        showAlertSheet()
    }
}
