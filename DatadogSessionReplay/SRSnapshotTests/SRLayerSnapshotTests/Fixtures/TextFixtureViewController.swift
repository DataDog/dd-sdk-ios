/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

@available(iOS 16.0, *)
internal final class TextFixtureViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let text = """
            Lorem ipsum dolor sit amet, consectetur adipiscing elit. \
            Mauris vestibulum consectetur dolor at vulputate. Sed eu \
            libero et metus scelerisque porta. Cras eu lorem orci.
            """

        let heading = UILabel()
        heading.text = "Heading"
        heading.font = .preferredFont(forTextStyle: .title1)

        let paragraph = UILabel()
        paragraph.numberOfLines = 0
        paragraph.font = .preferredFont(forTextStyle: .body)
        let attributedText = NSMutableAttributedString(string: text)
        attributedText.addAttribute(
            .font,
            value: UIFont.boldSystemFont(ofSize: paragraph.font.pointSize),
            range: (text as NSString).range(of: "Lorem ipsum dolor")
        )
        paragraph.attributedText = attributedText

        let button = UIButton(type: .system)
        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.title = "Click me!"
        button.configuration = buttonConfiguration

        let emptyField = UITextField()
        emptyField.placeholder = "Placeholder"
        emptyField.borderStyle = .roundedRect

        let populatedField = UITextField()
        populatedField.placeholder = "Text field placeholder"
        populatedField.text = "Lorem ipsum dolor sit amet"
        populatedField.borderStyle = .roundedRect

        let emailField = UITextField()
        emailField.placeholder = "Email address"
        emailField.textContentType = .emailAddress
        emailField.text = "jane.doe@example.com"
        emailField.borderStyle = .roundedRect

        let secureField = UITextField()
        secureField.placeholder = "Secure field placeholder"
        secureField.isSecureTextEntry = true
        secureField.text = "Lorem ipsum dolor sit amet"
        secureField.borderStyle = .roundedRect

        let textView = UITextView()
        textView.text = text
        textView.font = .preferredFont(forTextStyle: .body)
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        let stack = UIStackView(arrangedSubviews: [
            heading, paragraph, button, emptyField, populatedField, emailField, secureField, textView
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            textView.heightAnchor.constraint(equalToConstant: 140)
        ])
    }
}
