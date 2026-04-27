export namespace main {
	
	export class BenchmarkResult {
	    mode: string;
	    encryptMs: number;
	    decryptMs: number;
	    throughputMBps: number;
	
	    static createFrom(source: any = {}) {
	        return new BenchmarkResult(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.mode = source["mode"];
	        this.encryptMs = source["encryptMs"];
	        this.decryptMs = source["decryptMs"];
	        this.throughputMBps = source["throughputMBps"];
	    }
	}
	export class DecryptRequest {
	    inputPath: string;
	    outputPath: string;
	    keyHex: string;
	
	    static createFrom(source: any = {}) {
	        return new DecryptRequest(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.inputPath = source["inputPath"];
	        this.outputPath = source["outputPath"];
	        this.keyHex = source["keyHex"];
	    }
	}
	export class DecryptResult {
	    success: boolean;
	    elapsedMs: number;
	    bytesProcessed: number;
	    message: string;
	
	    static createFrom(source: any = {}) {
	        return new DecryptResult(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.success = source["success"];
	        this.elapsedMs = source["elapsedMs"];
	        this.bytesProcessed = source["bytesProcessed"];
	        this.message = source["message"];
	    }
	}
	export class EncryptRequest {
	    inputPath: string;
	    outputPath: string;
	    keyHex: string;
	    mode: string;
	
	    static createFrom(source: any = {}) {
	        return new EncryptRequest(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.inputPath = source["inputPath"];
	        this.outputPath = source["outputPath"];
	        this.keyHex = source["keyHex"];
	        this.mode = source["mode"];
	    }
	}
	export class EncryptResult {
	    success: boolean;
	    elapsedMs: number;
	    bytesProcessed: number;
	    message: string;
	
	    static createFrom(source: any = {}) {
	        return new EncryptResult(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.success = source["success"];
	        this.elapsedMs = source["elapsedMs"];
	        this.bytesProcessed = source["bytesProcessed"];
	        this.message = source["message"];
	    }
	}

}

