import SwiftUI

/// The document-free start surface for the native cover editor.
struct CoverEditorHome: View {
    let projects: [CoverProject]
    let activeProjectID: UUID?
    let canCreate: Bool
    let openProject: (Int) -> Void
    let newEbook: () -> Void
    let newPrint: () -> Void
    let openImage: () -> Void
    let openTemplate: () -> Void

    private let base = Color(red:71.0/255,green:71.0/255,blue:71.0/255)
    private let panel = Color(red:37.0/255,green:37.0/255,blue:37.0/255)
    private let accent = Color(red:52.0/255,green:130.0/255,blue:246.0/255)

    var body: some View {
        HStack(spacing:0) {
            sidebar.frame(width:188)
            Rectangle().fill(.black.opacity(0.45)).frame(width:1)
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    title
                    actions
                    if !projects.isEmpty { projectSection }
                    dropTarget
                }
                .frame(maxWidth:680,alignment:.leading)
                .padding(.horizontal,34)
                .padding(.vertical,36)
                .frame(maxWidth:.infinity)
            }
            .background(panel)
        }
        .background(base)
        .foregroundStyle(Color(red:213.0/255,green:213.0/255,blue:213.0/255))
    }

    private var sidebar: some View {
        VStack(alignment:.leading,spacing:5) {
            Text("COVER CREATOR")
                .font(.system(size:10,weight:.bold))
                .tracking(1.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal,15)
                .padding(.top,18)
                .padding(.bottom,10)
            Label("Home",systemImage:"house.fill")
                .font(.system(size:12,weight:.semibold))
                .frame(maxWidth:.infinity,alignment:.leading)
                .padding(.horizontal,14)
                .frame(height:34)
                .background(accent.opacity(0.3))
            if !projects.isEmpty {
                Text("THIS DOCUMENT")
                    .font(.system(size:10,weight:.bold))
                    .tracking(1.3)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal,15)
                    .padding(.top,21)
                    .padding(.bottom,4)
                ForEach(projects.indices,id:\.self) { index in
                    Button { openProject(index) } label: {
                        Label(projects[index].name,systemImage:projects[index].type == .printFullWrap ? "book.closed":"photo")
                            .lineLimit(1)
                            .frame(maxWidth:.infinity,alignment:.leading)
                            .padding(.horizontal,14)
                            .frame(height:32)
                            .background(projects[index].id == activeProjectID ? Color.white.opacity(0.1) : .clear)
                    }
                    .buttonStyle(.plain)
                    .help("Open \(projects[index].name)")
                }
            }
            Spacer()
        }
    }

    private var title: some View {
        VStack(alignment:.leading,spacing:8) {
            Text("BOLD Writer")
                .font(.system(size:31,weight:.bold,design:.rounded))
            Text("Cover Creator")
                .font(.system(size:18,weight:.medium))
                .foregroundStyle(.secondary)
            Text("Create artwork for an eBook front cover or a print wrap.")
                .font(.system(size:13))
                .foregroundStyle(.secondary)
                .padding(.top,5)
        }
    }

    private var actions: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:10) {
                actionButton("New eBook Cover",symbol:"plus.rectangle.portrait",primary:true,enabled:canCreate,action:newEbook)
                actionButton("New Print Wrap",symbol:"book.closed",primary:false,enabled:canCreate,action:newPrint)
            }
            HStack(spacing:10) {
                actionButton("Open Image or PSD",symbol:"photo.on.rectangle",primary:false,enabled:canCreate,action:openImage)
                actionButton("Open Cover Template",symbol:"doc.viewfinder",primary:false,enabled:canCreate,action:openTemplate)
            }
        }
    }

    private func actionButton(_ title:String,symbol:String,primary:Bool,enabled:Bool,action:@escaping ()->Void) -> some View {
        Button(action:action) {
            HStack(spacing:9) {
                Image(systemName:symbol).font(.system(size:16)).frame(width:21)
                Text(title).font(.system(size:12,weight:.semibold)).lineLimit(2)
                Spacer(minLength:0)
            }
            .padding(.horizontal,13)
            .frame(maxWidth:.infinity,minHeight:51)
            .background(primary ? accent : base)
            .clipShape(RoundedRectangle(cornerRadius:5))
            .overlay(RoundedRectangle(cornerRadius:5).stroke(.white.opacity(0.12),lineWidth:1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

    private var projectSection: some View {
        VStack(alignment:.leading,spacing:9) {
            Text("Covers in this document")
                .font(.system(size:12,weight:.semibold))
            ForEach(projects.indices,id:\.self) { index in
                Button { openProject(index) } label: {
                    HStack(spacing:11) {
                        Image(systemName:projects[index].type == .printFullWrap ? "book.closed":"rectangle.portrait")
                            .frame(width:22)
                            .foregroundStyle(accent)
                        VStack(alignment:.leading,spacing:2) {
                            Text(projects[index].name).fontWeight(.medium)
                            Text("\(projects[index].type.displayName) · \(Int(projects[index].canvasWidth * projects[index].dpi)) × \(Int(projects[index].canvasHeight * projects[index].dpi)) px")
                                .font(.system(size:10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName:"chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(11)
                    .background(base)
                    .clipShape(RoundedRectangle(cornerRadius:5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(projects[index].name)")
            }
        }
    }

    private var dropTarget: some View {
        VStack(spacing:7) {
            Image(systemName:"square.and.arrow.down").font(.system(size:23))
            Text("Drop an image or cover template here")
                .font(.system(size:13,weight:.medium))
            Text("You can choose whether to add it as artwork or a reference template.")
                .font(.system(size:11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth:.infinity,minHeight:130)
        .overlay(RoundedRectangle(cornerRadius:6).stroke(.white.opacity(0.28),style:StrokeStyle(lineWidth:1,dash:[6,5])))
        .accessibilityLabel("Drop an image or cover template")
    }
}
