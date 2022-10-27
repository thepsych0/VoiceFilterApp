import UIKit

extension UIControl {
    func addAction(for controlEvents: UIControl.Event = .touchUpInside, _ closure: @escaping () -> Void) {
        @objc class Closure: NSObject {
            let closure: () -> Void
            init(_ closure: @escaping () -> Void) { self.closure = closure }
            @objc func invoke() { closure() }
        }

        let closure = Closure(closure)
        addTarget(closure, action: #selector(Closure.invoke), for: controlEvents)
        objc_setAssociatedObject(self, "\(UUID())", closure, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
    }
}
