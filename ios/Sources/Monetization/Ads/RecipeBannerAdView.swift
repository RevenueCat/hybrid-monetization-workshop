import GoogleMobileAds
@_spi(Experimental) import RevenueCatAdMob
import SwiftUI

struct RecipeBannerAdView: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @EnvironmentObject private var ads: AdSupportStore
    @Binding var height: CGFloat

    var body: some View {
        if ads.adsEnabled, let configuration = AdConfiguration.bundled() {
            GeometryReader { proxy in
                let width = max(1, proxy.size.width)
                let size = largeAnchoredAdaptiveBanner(width: width)
                CollapsibleRecipeBanner(
                    width: width,
                    adUnitID: configuration.bannerAdUnitID,
                    placement: configuration.bannerPlacement
                )
                .frame(width: size.size.width, height: size.size.height)
                .frame(maxWidth: .infinity)
                .id(Int(width.rounded()))
                .task(id: Int(width.rounded())) { height = size.size.height }
            }
            .frame(height: height)
            .background { Color(uiColor: appearance.theme.paper).ignoresSafeArea(edges: .bottom) }
            .overlay(alignment: .top) {
                Rectangle().fill(Color(uiColor: appearance.theme.line)).frame(height: 0.5)
            }
        }
    }
}

private struct CollapsibleRecipeBanner: UIViewRepresentable {
    let width: CGFloat
    let adUnitID: String
    let placement: String

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: largeAnchoredAdaptiveBanner(width: width))
        banner.adUnitID = adUnitID
        banner.rootViewController = ViewControllerLocator.topViewController

        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["collapsible": "bottom"]
        request.register(extras)
        banner.loadAndTrack(request: request, placement: placement)
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        if banner.rootViewController == nil {
            banner.rootViewController = ViewControllerLocator.topViewController
        }
    }
}
