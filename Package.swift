import PackageDescription

let package = Package(
    name: "Consultation",
    dependencies: [
        .Package(url: "https://github.com/vapor/vapor.git", majorVersion: 1, minor: 5),
        .Package(url: "https://github.com/vapor/mysql-provider.git", majorVersion: 1),
        .Package(url:"https://github.com/vapor/jwt.git", majorVersion: 0, minor: 8),
        .Package(url: "https://github.com/brokenhandsio/LeafMarkdown.git", majorVersion: 0),
        .Package(url: "https://github.com/onevcat/Hedwig.git", majorVersion: 1),
        .Package(url: "https://github.com/soffes/Base62.git", majorVersion: 0)



    ],
    exclude: [
        "Config",
        "Database",
        "Localization",
        "Public",
        "Resources",
        "Tests",
        "FilePacks",
        "TemplatePacks",
    ]
)

