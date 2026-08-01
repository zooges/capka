import SwiftUI

struct RootView: View {
  @State private var canGoBack = false
  @State private var isLoading = false
  @State private var loadError: String?
  @State private var reloadToken = UUID()

  private var cream: Color {
    Color(red: AppConfig.brandCream.r, green: AppConfig.brandCream.g, blue: AppConfig.brandCream.b)
  }

  private var burgundy: Color {
    Color(red: AppConfig.brandBurgundy.r, green: AppConfig.brandBurgundy.g, blue: AppConfig.brandBurgundy.b)
  }

  var body: some View {
    ZStack {
      cream.ignoresSafeArea()

      CapkaWebView(
        canGoBack: $canGoBack,
        isLoading: $isLoading,
        loadError: $loadError,
        reloadToken: reloadToken
      )
      .ignoresSafeArea()

      if isLoading {
        VStack {
          ProgressView()
            .tint(burgundy)
            .padding(.top, 8)
          Spacer()
        }
        .allowsHitTesting(false)
      }

      if let loadError {
        VStack(spacing: 16) {
          Image(systemName: "wifi.exclamationmark")
            .font(.system(size: 40))
            .foregroundStyle(burgundy)
          Text("无法连接")
            .font(.headline)
          Text(loadError)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
          Button("重试") {
            self.loadError = nil
            reloadToken = UUID()
          }
          .buttonStyle(.borderedProminent)
          .tint(burgundy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cream.opacity(0.96))
      }
    }
    .statusBarHidden(false)
    .preferredColorScheme(.light)
  }
}
