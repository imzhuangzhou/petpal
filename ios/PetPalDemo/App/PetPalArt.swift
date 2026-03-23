import SwiftUI

enum PetPalArtAsset: String {
    case petCat = "ArtPetCat"
    case petDog = "ArtPetDog"
    case petCatBritish = "ArtPetCatBritish"
    case petCatSiamese = "ArtPetCatSiamese"
    case petCatRagdoll = "ArtPetCatRagdoll"
    case petDogCorgi = "ArtPetDogCorgi"
    case petDogGolden = "ArtPetDogGolden"
    case petDogShiba = "ArtPetDogShiba"
    case styleTsundere = "ArtStyleTsundere"
    case styleLoyal = "ArtStyleLoyal"
    case styleChatty = "ArtStyleChatty"
    case styleChill = "ArtStyleChill"
    case featureHealth = "ArtFeatureHealth"
    case featureReport = "ArtFeatureReport"
    case featureAnxiety = "ArtFeatureAnxiety"
    case featureDiary = "ArtFeatureDiary"
    case featureRadar = "ArtFeatureRadar"
    case avatarPalette = "ArtAvatarPalette"
    case alertCritical = "ArtAlertCritical"
    case alertWarning = "ArtAlertWarning"
    case alertSuccess = "ArtAlertSuccess"

    var imageName: String { rawValue }

    var placeholderColors: [Color] {
        switch self {
        case .petCat, .petCatBritish, .petCatSiamese, .petCatRagdoll, .styleTsundere:
            return [Color(hex: "F7C39B"), Color(hex: "E39A71")]
        case .petDog, .petDogCorgi, .petDogGolden, .petDogShiba, .styleLoyal:
            return [Color(hex: "DDBB93"), Color(hex: "C08B5F")]
        case .styleChatty, .featureReport:
            return [Color(hex: "CFE8D8"), Color(hex: "9BC9B0")]
        case .styleChill, .featureDiary:
            return [Color(hex: "E5DCCF"), Color(hex: "C8B9A8")]
        case .featureHealth, .alertSuccess:
            return [Color(hex: "DFF1E2"), Color(hex: "A8D3AE")]
        case .featureAnxiety, .alertWarning:
            return [Color(hex: "FFF0D7"), Color(hex: "F4C98B")]
        case .featureRadar:
            return [Color(hex: "FFE7D7"), Color(hex: "F6B992")]
        case .avatarPalette:
            return [Color(hex: "FFF1E3"), Color(hex: "F1C9AE")]
        case .alertCritical:
            return [Color(hex: "FFE2DD"), Color(hex: "F4B1A4")]
        }
    }

    static func pet(for species: String) -> PetPalArtAsset {
        species == "dog" ? .petDog : .petCat
    }

    static func style(for styleID: String) -> PetPalArtAsset {
        switch styleID {
        case "loyal":
            return .styleLoyal
        case "chatty":
            return .styleChatty
        case "chill":
            return .styleChill
        default:
            return .styleTsundere
        }
    }

    static func healthAlert(for level: String) -> PetPalArtAsset {
        switch level {
        case "critical":
            return .alertCritical
        case "warning":
            return .alertWarning
        default:
            return .alertSuccess
        }
    }
}

struct PetPalArtImage: View {
    let asset: PetPalArtAsset

    var body: some View {
        Image(asset.imageName)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
    }
}
