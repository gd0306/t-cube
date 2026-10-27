import { Vector3 } from 'three';

/** Native SlimeMotion.swift deformation, in cube-local coordinates. */
export class SlimeDeformation {
    contact = new Vector3(0, 0, 0.5);
    pull = 0;
    shear = new Vector3();
    private readonly displacement = new Vector3();
    private readonly difference = new Vector3();

    private updateDisplacement(): Vector3 {
        const { x, y, z } = this.contact;
        return this.displacement.set(x * x * x, y * y * y, z * z * z)
            .normalize().multiplyScalar(this.pull).add(this.shear);
    }

    position(point: Vector3, target = new Vector3()): Vector3 {
        const weight = Math.exp(-9 * point.distanceToSquared(this.contact));
        const displacement = this.updateDisplacement();
        return target.copy(point).multiplyScalar(1 - 0.06 * this.pull).addScaledVector(displacement, weight);
    }

    normal(normal: Vector3, point: Vector3, target = new Vector3()): Vector3 {
        const gradient = this.difference.subVectors(point, this.contact);
        gradient.multiplyScalar(-18 * Math.exp(-9 * gradient.lengthSq()));
        const displacement = this.updateDisplacement();
        const denominator = 1 - 0.06 * this.pull + gradient.dot(displacement);
        const adjustment = displacement.dot(normal) / Math.max(0.2, denominator);
        // Inverse transpose of the deformation Jacobian keeps highlights on the bent surface.
        return target.copy(normal).addScaledVector(gradient, -adjustment).normalize();
    }
}

export class SlimeMotion {
    readonly deformation = new SlimeDeformation();
    private readonly target = new Vector3();
    private readonly lag = new Vector3();
    private readonly targetShear = new Vector3();
    private hasContact = false;
    private velocity = 0;

    get isActive(): boolean {
        return this.hasContact || Math.abs(this.deformation.pull) > 0.00001
            || Math.abs(this.velocity) > 0.0001 || this.deformation.shear.length() > 0.00001;
    }

    setContact(point: Vector3 | null): void {
        if (!point || !Number.isFinite(point.x) || !Number.isFinite(point.y)
            || !Number.isFinite(point.z) || point.lengthSq() <= 0.01) {
            this.hasContact = false;
            return;
        }
        this.target.copy(point).clampScalar(-0.7, 0.7);
        if (!this.isActive) this.deformation.contact.copy(this.target);
        this.hasContact = true;
    }

    step(deltaTime: number, reducedMotion: boolean): void {
        if (!Number.isFinite(deltaTime) || deltaTime <= 0) return;
        if (reducedMotion) {
            this.deformation.pull = 0;
            this.deformation.shear.set(0, 0, 0);
            this.velocity = 0;
            this.hasContact = false;
            return;
        }
        let remaining = Math.min(deltaTime, 0.05);
        while (remaining > 0) {
            const step = Math.min(remaining, 1 / 120);
            const targetPull = this.hasContact ? 0.13 : 0;
            this.velocity += ((targetPull - this.deformation.pull) * 260 - this.velocity * 12) * step;
            this.deformation.pull += this.velocity * step;
            if (this.hasContact) {
                this.lag.subVectors(this.target, this.deformation.contact);
                this.deformation.contact.addScaledVector(this.lag, 1 - Math.exp(-step / 0.075));
                this.targetShear.copy(this.lag).multiplyScalar(0.4);
                const length = this.targetShear.length();
                if (length > 0.09) this.targetShear.multiplyScalar(0.09 / length);
                this.deformation.shear.lerp(this.targetShear, 1 - Math.exp(-step / 0.045));
            } else {
                this.deformation.shear.multiplyScalar(Math.exp(-step / 0.12));
            }
            remaining -= step;
        }
        if (!this.hasContact && Math.abs(this.deformation.pull) < 0.00001
            && Math.abs(this.velocity) < 0.0001 && this.deformation.shear.length() < 0.00001) {
            this.deformation.pull = 0;
            this.deformation.shear.set(0, 0, 0);
            this.velocity = 0;
        }
    }
}
